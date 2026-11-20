defmodule FGDataCatalogWeb.UserAuth do
  @moduledoc """
  The signed-in user of a request or LiveView, as `@current_scope` (see
  `FGDataCatalog.Accounts.Scope`; `nil` for visitors).

  NOTE(Claude 2026-11-06): the session holds the raw session token
  (`"user_token"`) and the `"live_socket_id"` of the user's LiveViews, through
  which signing out disconnects them.
  """
  use FGDataCatalogWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias FGDataCatalog.Accounts
  alias FGDataCatalog.Accounts.Scope

  @doc "Plug: assigns `:current_scope` from the session token."
  def fetch_current_scope(conn, _opts) do
    user = conn |> get_session("user_token") |> Accounts.get_user_by_session_token()
    assign(conn, :current_scope, Scope.for_user(user))
  end

  @doc """
  Signs `user` in and goes back to the catalog. The session is renewed (a new
  id, the old content dropped) so that a session id planted before signing in
  is worthless after.
  """
  def log_in_user(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> renew_session()
    |> put_session("user_token", token)
    |> put_session("live_socket_id", live_socket_id(token))
    |> redirect(to: ~p"/")
  end

  @doc "Signs out: ends the session, disconnects its LiveViews."
  def log_out_user(conn) do
    token = get_session(conn, "user_token")
    Accounts.delete_user_session_token(token)

    if live_socket_id = get_session(conn, "live_socket_id") do
      FGDataCatalogWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> redirect(to: ~p"/")
  end

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp live_socket_id(token), do: "users_sessions:#{Base.url_encode64(token)}"

  @doc """
  LiveView `on_mount`: `:mount_current_scope` assigns `:current_scope` from the
  session token. Each LiveView then decides what the scope may see or do.
  """
  def on_mount(:mount_current_scope, _params, session, socket) do
    {:cont,
     Phoenix.Component.assign_new(socket, :current_scope, fn ->
       session["user_token"] |> Accounts.get_user_by_session_token() |> Scope.for_user()
     end)}
  end
end
