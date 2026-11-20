defmodule FGDataCatalogWeb.AuthController do
  @moduledoc """
  Sign-in with Google, and sign-out.

  NOTE(Claude 2026-11-06): `request` sends the browser to Google with a random
  `state` and `nonce`, kept in the session; `callback` is where Google sends it
  back. The `state` must match (the sign-in was started here, by this
  browser), and the ID token's `nonce` too (the token was issued for this
  sign-in).
  """
  use FGDataCatalogWeb, :controller

  require Logger

  alias FGDataCatalog.Accounts
  alias FGDataCatalog.Accounts.Google
  alias FGDataCatalogWeb.UserAuth

  def request(conn, _params) do
    if Google.configured?() do
      state = Google.random_token()
      nonce = Google.random_token()

      conn
      |> put_session("google_auth", %{"state" => state, "nonce" => nonce})
      |> redirect(external: Google.authorize_url(redirect_uri(), state, nonce))
    else
      conn
      |> put_flash(:error, "Sign-in with Google is not configured.")
      |> redirect(to: ~p"/")
    end
  end

  def callback(conn, params) do
    stored = get_session(conn, "google_auth")
    conn = delete_session(conn, "google_auth")

    with %{"state" => state, "nonce" => nonce} <- stored,
         %{"state" => returned, "code" => code} when is_binary(returned) and is_binary(code) <-
           params,
         true <- Plug.Crypto.secure_compare(returned, state),
         {:ok, claims} <- Google.fetch_claims(code, redirect_uri(), nonce),
         {:ok, user} <- Accounts.upsert_google_user(claims) do
      UserAuth.log_in_user(conn, user)
    else
      error ->
        Logger.info("Google sign-in refused: #{inspect(reason(error, params))}")

        conn
        |> put_flash(:error, message(reason(error, params)))
        |> redirect(to: ~p"/")
    end
  end

  def delete(conn, _params), do: UserAuth.log_out_user(conn)

  # NOTE(Claude 2026-11-06): must be the same in the authorize and token
  # requests, and registered in the Google OAuth client: built from the
  # endpoint's URL (`PHX_HOST` in production).
  defp redirect_uri, do: url(~p"/auth/google/callback")

  defp reason(_error, %{"error" => "access_denied"}), do: :cancelled
  defp reason({:error, %Ecto.Changeset{}}, _params), do: :user_not_saved
  defp reason({:error, reason}, _params), do: reason
  defp reason(_error, _params), do: :invalid_state

  defp message(:cancelled), do: "Sign-in cancelled."
  defp message(:wrong_domain), do: "Sign in with your @finngen.fi Google account."
  defp message(_reason), do: "Sign-in with Google failed. Please try again."
end
