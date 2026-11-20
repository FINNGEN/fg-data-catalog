#!/usr/bin/env bash
# NOTE(Claude Opus 5.5 2026-11-18): sets up (or updates) the production VM for
# the catalog's deploys (see deploy/README.md). Run as root from a copy of
# deploy/vm/, as `deploy/fgdc setup` does from the Mac:
#
#   sudo bash setup.sh [DEPLOY_USER]
#
# DEPLOY_USER (default: the user running sudo) may send releases: it joins the
# fgdc-deploy group. Safe to run again: it never touches the database, the
# releases or an existing /etc/fgdc/env.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=/srv/fgdc
DEPLOY_USER=${1:-${SUDO_USER:-}}

[ "$(id -u)" -eq 0 ] || { echo "setup.sh: run as root (sudo)" >&2; exit 1; }
# NOTE(Claude Opus 5.5 2026-11-18): the release is built for Debian 13 arm64
# (deploy/Containerfile); it would not start on an older Debian.
. /etc/os-release
[ "${VERSION_CODENAME:-}" = trixie ] && [ "$(dpkg --print-architecture)" = arm64 ] ||
  { echo "setup.sh: this VM is $PRETTY_NAME $(dpkg --print-architecture); the releases are built for Debian 13 (trixie) arm64" >&2; exit 1; }

echo "== Packages"
apt-get update -qq
apt-get install -y -qq zstd curl ca-certificates libstdc++6 libncurses6 libssl3t64 libsctp1 > /dev/null

echo "== Users and groups"
getent group fgdc-deploy > /dev/null || groupadd --system fgdc-deploy
id fgdc > /dev/null 2>&1 ||
  useradd --system --user-group --home-dir "$ROOT" --no-create-home --shell /usr/sbin/nologin fgdc
# NOTE(Claude Opus 5.5 2026-11-18): gpasswd, not usermod: it finds the user
# through NSS, so it also works for a GCP OS Login user (not in /etc/passwd).
if [ -n "$DEPLOY_USER" ] && [ "$DEPLOY_USER" != root ]; then
  if gpasswd -a "$DEPLOY_USER" fgdc-deploy > /dev/null; then
    echo "$DEPLOY_USER may deploy (log in again for the group to apply)"
  else
    echo "WARNING: could not add $DEPLOY_USER to the fgdc-deploy group; add the user who sends releases by hand" >&2
  fi
fi

echo "== Directories under $ROOT"
# NOTE(Claude Opus 5.5 2026-11-18): the deploy group writes to upload/ and
# incoming/ and reads logs/; the app's user owns its database and backups.
install -d -m 755 -o root -g root "$ROOT" "$ROOT/bin" "$ROOT/releases"
install -d -m 2770 -o root -g fgdc-deploy "$ROOT/upload" "$ROOT/incoming"
install -d -m 2750 -o root -g fgdc-deploy "$ROOT/logs"
install -d -m 750 -o root -g root "$ROOT/failed"
install -d -m 750 -o fgdc -g fgdc "$ROOT/data" "$ROOT/backups" "$ROOT/tmp"
[ -f "$ROOT/deploys.log" ] || install -m 640 -o root -g fgdc-deploy /dev/null "$ROOT/deploys.log"
install -m 755 "$HERE/fgdc-deploy" "$ROOT/bin/fgdc-deploy"

echo "== /etc/fgdc/env"
install -d -m 750 -o root -g root /etc/fgdc
if [ ! -f /etc/fgdc/env ]; then
  secret=$(head -c 48 /dev/urandom | base64 -w0 | tr '+/' '-_')
  sed "s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$secret|" "$HERE/env.example" > /etc/fgdc/env
  chmod 600 /etc/fgdc/env
  echo "Created /etc/fgdc/env: fill in PHX_HOST, GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET"
else
  echo "Kept the existing /etc/fgdc/env"
fi

echo "== systemd units"
install -m 644 "$HERE/fgdc.service" "$HERE/fgdc-deploy.service" "$HERE/fgdc-deploy.path" /etc/systemd/system/
systemctl daemon-reload
systemctl enable fgdc.service
systemctl enable --now fgdc-deploy.path

echo
echo "Done. Next, if not done yet:"
echo "  * fill in /etc/fgdc/env (sudoedit /etc/fgdc/env)"
echo "  * add to the Caddyfile (see deploy/vm/Caddyfile.example) and reload Caddy"
echo "  * from the Mac: mix deploy"
