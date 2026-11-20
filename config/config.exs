# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :fg_data_catalog,
  namespace: FGDataCatalog,
  ecto_repos: [FGDataCatalog.Repo],
  generators: [timestamp_type: :utc_datetime]

# NOTE(Claude 2026-11-06): sign-in with Google is open to the accounts of this
# Google Workspace domain only. The OAuth client is set in `config/runtime.exs`.
config :fg_data_catalog, FGDataCatalog.Accounts.Google, hosted_domain: "finngen.fi"

# Configure the endpoint
config :fg_data_catalog, FGDataCatalogWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FGDataCatalogWeb.ErrorHTML, json: FGDataCatalogWeb.ErrorJSON],
    # NOTE(Claude Opus 5.5 2026-11-18): the error pages in the root layout
    # (app.css, favicon, theme); `ErrorHTML` draws its own static header.
    root_layout: [html: {FGDataCatalogWeb.Layouts, :root}],
    layout: false
  ],
  pubsub_server: FGDataCatalog.PubSub,
  live_view: [signing_salt: "3hP83++X"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  fg_data_catalog: [
    args:
      ~w(js/app.js css/app.css --bundle --target=es2022 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
