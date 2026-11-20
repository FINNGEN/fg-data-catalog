defmodule FGDataCatalog.Repo do
  use Ecto.Repo,
    otp_app: :fg_data_catalog,
    adapter: Ecto.Adapters.SQLite3
end
