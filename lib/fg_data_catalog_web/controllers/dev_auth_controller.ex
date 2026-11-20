defmodule FGDataCatalogWeb.DevAuthController do
  @moduledoc """
  NOTE(Claude 2026-11-06): development only: signs in as a made-up user
  without Google, as one of two editors (to try a Draft's owning editor and
  another editor side by side), locally. Its routes exist
  only with `dev_routes` (set in `config/dev.exs` only, decided at compile
  time, see the router).
  """
  use FGDataCatalogWeb, :controller

  alias FGDataCatalog.Accounts
  alias FGDataCatalogWeb.UserAuth

  @users %{
    "editor" => %{sub: "dev:editor", email: "dev-editor@finngen.fi", name: "Dev Editor"},
    # NOTE(Claude 2026-11-16): was an admin; there are no admins any more.
    "other-editor" => %{
      sub: "dev:other-editor",
      email: "dev-other-editor@finngen.fi",
      name: "Dev Other Editor"
    }
  }

  def new(conn, _params) do
    render(conn, :new, users: @users)
  end

  def create(conn, %{"role" => role}) when is_map_key(@users, role) do
    {:ok, user} = Accounts.upsert_google_user(Map.fetch!(@users, role))
    UserAuth.log_in_user(conn, user)
  end
end
