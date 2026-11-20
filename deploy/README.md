# Deploying

<!-- NOTE(Claude Opus 5.5 2026-11-18) -->

The catalog runs on a Debian 13 VM (GCP N4A, arm64) as a [Mix release][release]
under systemd, behind Caddy (on another VM). A deploy is one file sent from the
Mac: the VM watches a folder and does the rest.

```sh
mix deploy                         # build, send, wait for the result
mix deploy.rollback                # back to the release before the current one
mix deploy.status                  # current release and last deploys
deploy/fgdc replace-db             # replace the production database with the dev one
```

[release]: https://hexdocs.pm/mix/Mix.Tasks.Release.html

## What happens

On the Mac, `deploy/fgdc deploy` (what `mix deploy` runs):

1. builds the release in a Debian 13 arm64 container (Podman; native on an
   Apple Silicon Mac, about 10 seconds after a code change):
   `_build/deploy/fg_data_catalog-<ID>.tar.zst`, with the Erlang runtime in
   it. `<ID>` is the commit's time and id, e.g. `20261118T074924Z-89ad54dee573`:
   the parent of the working copy after `jj commit`, else the working copy
   itself (with a warning);
2. sends it to `fgdc-prod:/srv/fgdc/incoming/` (through `upload/`, so that the
   VM never sees half a file);
3. prints the VM's log of the deploy as it goes, and exits with its result.

On the VM, `fgdc-deploy.path` sees the file and runs
`/srv/fgdc/bin/fgdc-deploy`, which:

1. unpacks the release into `/srv/fgdc/releases/<ID>/`;
2. stops the app (5 to 10 seconds of downtime; open pages reconnect by
   themselves) and backs up the database to `/srv/fgdc/backups/`;
3. migrates the database and checks the changelog (`mix changelog.verify`)
   with the new release;
4. points `/srv/fgdc/current` at it and starts the app;
5. checks that it answers.

If any step fails, it restores the backup, starts the previous release again,
and `mix deploy` exits with an error. Migrations only ever run there, after a
backup: the app does not migrate when it starts.

The last 5 releases and 5 backups are kept.

## Rolling back

```sh
mix deploy.rollback                     # to the release the current one was deployed over
mix deploy.rollback <ID>                # to a release still on the VM (see mix deploy.status)
mix deploy.rollback --restore-backup    # see below
```

A rollback is a switch of release like a deploy (with its own backup first,
and the same recovery if it fails), except for the database:

- **By default, the data is kept.** The migrations that the older release does
  not know are rolled back with the newer release's code (their `down`, which
  also rewrites the changelog; see `AGENTS.md`), then the changelog is checked
  with the older release.
- **With `--restore-backup`**, the database is put back as it was when the
  current release was deployed, from the backup taken then. Anything changed
  since is lost from the live database (it stays in the backup taken just
  before the rollback). For when a `down` migration fails or the new release
  damaged data. Only to the release the current one was deployed over.

Rolling back again keeps going back (A → B → C, rollback to B, rollback to A).
Sending an older tarball (`deploy/fgdc deploy <file>`) works too, and is
handled like a rollback that keeps the data.

If the Mac is not at hand: `ssh fgdc-prod sudo /srv/fgdc/bin/fgdc-deploy rollback`
(same options).

## Replacing the database

<!-- NOTE(Claude Opus 5.5 2026-11-19) -->

```sh
deploy/fgdc replace-db                  # with the dev database
deploy/fgdc replace-db path/to/other.db # with another one; --yes skips the question
mix deploy.replace_db --yes             # the same through mix: --yes is needed
mix deploy.restore_backup <NAME>        # put back a backup of the VM's
```

`deploy/fgdc replace-db` makes a consistent copy of the database
(`sqlite3 .backup`: the dev one is in WAL mode, and may be in use), removes
its login sessions (`users_tokens`), checks its changelog with this checkout's
code, prints what it holds, and asks to type `replace`. Then it sends the copy
(`DATABASE-<time>.db`), and the VM handles it as a switch from the current
release to itself:

1. stops the app and backs up the database it replaces;
2. puts the copy in its place;
3. migrates it and checks the changelog with the current release; **refuses a
   database with migrations the release does not know** (e.g. a dev database
   migrated ahead of the deployed code: deploy that code first);
4. starts the app and checks that it answers.

If any step fails, the replaced database is put back, and the copy is kept in
`/srv/fgdc/failed/`. Each replacement is a `database` line in
`mix deploy.status`, with its backup in the last column.

To undo it, `mix deploy.restore_backup <NAME>` with that backup's file name:
the same switch, from a file of `/srv/fgdc/backups/` (the database it replaces
is backed up first too). Not `mix deploy.rollback --restore-backup`: that
puts back the backup taken when the current release was deployed, from
before the replacement. Only the last 5 backups are kept.

Without the Mac: `ssh fgdc-prod sudo /srv/fgdc/bin/fgdc-deploy restore-backup <NAME>`.

## Logs

- `mix deploy.status`: the current release, whether the app runs, the
  releases on the VM, the last lines of `/srv/fgdc/deploys.log` (one line per
  switch: time, action, from, to, backup, result).
- `deploy/fgdc log [NAME]`: the log of a deploy or rollback (default: the
  last), from `/srv/fgdc/logs/`.
- On the VM: `journalctl -u fgdc` (the app), `journalctl -u fgdc-deploy`.

## Setting up

### The Mac, once

- Podman, and its build machine: `deploy/fgdc build-machine` creates
  `fgdc-build` (6 GB). The other Podman machines are not used or changed.
  It keeps the build cache (`_build` in a cache mount, see
  `deploy/Containerfile`): a first build takes about 40 seconds, one after a
  code change about 10. To build from scratch, remove the machine
  (`podman machine rm fgdc-build`) and create it again.
- `~/.ssh/config` has a `fgdc-prod` entry for the VM (or set
  `FGDC_DEPLOY_HOST`).

### The VM, once

0. The VM: an N4A machine with a Debian 13 ("trixie") arm64 image (the
   release is built on it; `setup.sh` checks). Caddy is on the proxy VM
   ([install](https://caddyserver.com/docs/install#debian-ubuntu-raspbian)
   if it is a new one).
1. `deploy/fgdc setup` (from the Mac; uses `sudo` on the VM). It installs
   `zstd` and `curl`, creates the `fgdc` user (runs the app) and the
   `fgdc-deploy` group (may send releases; your ssh user joins it, log in
   again), `/srv/fgdc/`, `/etc/fgdc/env` (with a new `SECRET_KEY_BASE`), and
   the systemd units. Run it again after changing anything in `deploy/vm/`:
   it never touches the database, the releases or an existing
   `/etc/fgdc/env`.
2. Fill in `/etc/fgdc/env` on the VM: `PHX_HOST`, `GOOGLE_CLIENT_ID`,
   `GOOGLE_CLIENT_SECRET` (see `deploy/vm/env.example`).
3. In the Google Cloud console, add
   `https://<PHX_HOST>/auth/google/callback` to the production OAuth client's
   redirect URIs.
4. On the proxy VM, add `deploy/vm/Caddyfile.example` to the Caddyfile, with
   the real host and the app VM's internal name, and
   `sudo systemctl reload caddy`. Its `handle_errors` block shows a
   "Back in a minute" page while the app is down (during a deploy, for
   instance, or when Caddy cannot reach it), for this site only.
   The app listens on every address of its VM (`LISTEN_IP=0.0.0.0` in
   `/etc/fgdc/env`); in the GCP firewall, allow `tcp:4994` to the app VM
   from the proxy VM's internal IP only, never from `0.0.0.0/0`. Check from
   the proxy VM: `curl -sI http://<app VM internal name>:4994/` answers
   (a redirect to https); "connection refused" at once means the app only
   listens on `127.0.0.1`, a wait then a timeout means the firewall.
5. In the GCP console, a snapshot schedule on the VM's disk: copies of the
   database off the VM (the backups in `/srv/fgdc/backups/` are on the same
   disk).
6. `mix deploy`.

### Layout on the VM

```
/etc/fgdc/env                 secrets and settings (root, 600)
/srv/fgdc/
  current -> releases/<ID>    the running release
  releases/<ID>/              the last 5 releases
  data/fg_data_catalog.db     the database (fgdc)
  backups/                    the last 5 backups (fgdc)
  upload/  incoming/          files sent from the Mac (fgdc-deploy group)
  logs/  deploys.log          deploy logs (readable by fgdc-deploy)
  failed/                     files that could not be handled
  bin/fgdc-deploy             from deploy/vm/
```

## Trying it on the Mac

Both run in the `fgdc-build` Podman machine.

**The release:** `deploy/test/smoke [TARBALL] [DATABASE]` runs the newest
tarball (the one `mix deploy` would send) on a plain Debian 13 container,
with a copy of the dev database: backup, migrations, changelog check, start,
the catalog page, the assets, the proxy headers. Optional: the VM does the
same checks and undoes a deploy that fails them; this only finds out before
sending.

**The deploy scripts:** `deploy/test/vm up` starts a stand-in for the VM
(Debian 13 arm64, systemd, sshd) and sets it up with `deploy/fgdc setup`, with
dummy Google secrets. It takes the same tarballs as production:

```sh
eval "$(deploy/test/vm env)"    # point deploy/fgdc at it
deploy/fgdc deploy
deploy/fgdc rollback
deploy/test/vm sh               # a root shell in it
deploy/test/vm down
```

To start from an existing database, copy it to
`/srv/fgdc/data/fg_data_catalog.db` (owned by `fgdc`) before the first deploy.

## Changing the domain

<!-- NOTE(Claude Opus 5.5 2026-11-18) -->

The domain is only in `PHX_HOST` (`/etc/fgdc/env`) and the Caddyfile: no
rebuild or deploy. The app builds its URLs from `PHX_HOST`: the Google
sign-in redirect URI, the origin LiveView's websockets must come from
(`check_origin`), the redirect to https. So all of these must agree, in this
order (`new.example.org` stands for the new domain):

1. **DNS:** an A record (and AAAA if used) for `new.example.org` to the VM's
   external IP. Keep the old one for now. Wait until
   `dig +short new.example.org` gives the VM's IP.
2. **Google Cloud console, the production OAuth client:** add
   `https://new.example.org/auth/google/callback` to the authorized redirect
   URIs (keep the old one for now). If the new domain is under a domain not
   yet listed, add it to the OAuth consent screen's authorized domains too.
3. **Caddyfile on the VM:** change the site address of the catalog's block
   to `new.example.org` (keep the rest: proxy, error page), and add a block
   for the old domain that sends visitors on:

   ```
   old.example.org {
   	redir https://new.example.org{uri} permanent
   }
   ```

   Then `sudo caddy validate --config /etc/caddy/Caddyfile` and
   `sudo systemctl reload caddy`; `journalctl -u caddy` shows the new
   certificate being obtained (port 80 must be open for it).
4. **`PHX_HOST=new.example.org`** in `/etc/fgdc/env` (`sudoedit
   /etc/fgdc/env`), then `sudo systemctl restart fgdc` (a few seconds of
   downtime). Between steps 3 and 4, pages load but do not connect
   (LiveView refuses the new origin) and signing in fails: do them one
   right after the other.
5. **Check:** open `https://new.example.org`, sign in with Google, edit
   something; `https://old.example.org/...` redirects to the same page on
   the new domain.

Everyone has to sign in again: the session cookie belongs to the old domain.
Later (weeks, once links and bookmarks have moved): remove the old redirect
URI from the OAuth client, the old site block and the old DNS record.

Also update `deploy/vm/Caddyfile.example` if it holds the real domain, and
the domain wherever it is written down (e.g. in `TODO.md` or in messages
pointing to the catalog).

## Notes

- Since the first deploy (2026-11-18), migrations can no longer be squashed
  into `create_schema` (see `AGENTS.md`). A squash would make the rollback step
  find every applied migration unknown; it refuses to roll back everything,
  so such a deploy fails and is undone.
- The app listens on `$LISTEN_IP:$PORT`: `0.0.0.0:4994` here (the proxy is
  on another VM, see `env.example`); `127.0.0.1` if `LISTEN_IP` is not set.
  The deploy's health check uses `127.0.0.1:$PORT`, so `LISTEN_IP` must
  include it (`0.0.0.0` or `127.0.0.1`, not the internal IP alone).
- A shell in the running app (`remote`), or any command of the release
  (e.g. `eval "..."`), as `fgdc` with `/etc/fgdc/env` loaded:

  ```sh
  sudo bash -c 'cd /srv/fgdc/tmp && set -a && . /etc/fgdc/env && set +a && runuser -u fgdc -- /srv/fgdc/current/bin/fg_data_catalog remote'
  ```

  The `cd` matters: the Erlang VM crashes at startup ("Kernel pid
  terminated (logger)", in `code_server`) if `fgdc` cannot read the current
  directory, e.g. your home.
