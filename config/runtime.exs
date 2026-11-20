import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/fg_data_catalog start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :fg_data_catalog, FGDataCatalogWeb.Endpoint, server: true
end

config :fg_data_catalog, FGDataCatalogWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# NOTE(Claude 2026-11-16): the Google OAuth client of this environment (one
# for development, one for production). Tests set their own, in
# `config/test.exs`. There are no admins any more (no `ADMIN_EMAILS`).
if config_env() != :test do
  config :fg_data_catalog, FGDataCatalog.Accounts.Google,
    client_id: System.get_env("GOOGLE_CLIENT_ID"),
    client_secret: System.get_env("GOOGLE_CLIENT_SECRET")
end

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :fg_data_catalog, FGDataCatalogWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/fg_data_catalog_web/router\.ex$"E,
        ~r"lib/fg_data_catalog_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/fg_data_catalog/fg_data_catalog.db
      """

  config :fg_data_catalog, FGDataCatalog.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5"),
    journal_mode: :wal,
    synchronous: :normal,
    busy_timeout: 5_000,
    foreign_keys: :on,
    cache_size: -64_000,
    temp_store: :memory,
    default_transaction_mode: :immediate

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # NOTE(Claude 2026-11-06): without them nobody can sign in: the Google OAuth
  # client of production, and the host its redirect URI is built from
  # (`https://<PHX_HOST>/auth/google/callback`, registered in the client).
  for name <- ~w(GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET PHX_HOST),
      System.get_env(name) in [nil, ""] do
    raise "environment variable #{name} is missing (needed to sign in with Google)"
  end

  host = System.get_env("PHX_HOST")

  listen_ip =
    case :inet.parse_address(String.to_charlist(System.get_env("LISTEN_IP", "127.0.0.1"))) do
      {:ok, ip} -> ip
      {:error, _} -> raise "environment variable LISTEN_IP is not an IP address"
    end

  config :fg_data_catalog, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :fg_data_catalog, FGDataCatalogWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # NOTE(Claude Opus 5.5 2026-11-18): the address to listen on, loopback by
      # default: Caddy, on the same machine, terminates HTTPS and proxies to
      # it. Set LISTEN_IP (e.g. "::" for every interface) if the proxy is on
      # another machine.
      ip: listen_ip
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :fg_data_catalog, FGDataCatalogWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :fg_data_catalog, FGDataCatalogWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
