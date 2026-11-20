import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :fg_data_catalog, FGDataCatalog.Repo,
  database: Path.expand("../fg_data_catalog_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox,
  # NOTE(Claude 2026-11-03): as in dev and prod. Each test runs in one sandbox
  # transaction; taking the write lock up front makes concurrent tests wait for
  # it instead of failing with "Database busy" when a read turns into a write.
  busy_timeout: 5_000,
  default_transaction_mode: :immediate

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :fg_data_catalog, FGDataCatalogWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Zu658B63sb17bVllBmO82d2CSsPGyKuk0DOA31FbPkpOtU6Jqfiue7vpzJmoJBa0",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# NOTE(Claude 2026-11-06): tests sign in as made-up users (see
# `FGDataCatalogWeb.ConnCase.log_in/2`). Google is stubbed with `Req.Test`.
config :fg_data_catalog, FGDataCatalog.Accounts.Google,
  client_id: "test-client-id",
  client_secret: "test-client-secret",
  req_options: [plug: {Req.Test, FGDataCatalog.Accounts.Google}]

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
