defmodule FGDataCatalog.Accounts do
  @moduledoc """
  The people who sign in (with Google, see `FGDataCatalog.Accounts.Google`)
  and their sessions.
  """
  import Ecto.Query, warn: false

  alias FGDataCatalog.Repo
  alias FGDataCatalog.Accounts.{User, UserToken}

  @doc """
  Returns the user of a Google account, created on first sign-in. The email
  and name follow those of the account. `claims` are those Google vouched for:
  `:sub`, `:email` and `:name`.
  """
  def upsert_google_user(%{sub: sub, email: email} = claims) do
    attrs = %{google_sub: sub, email: email, name: claims[:name]}

    (Repo.get_by(User, google_sub: sub) || %User{})
    |> User.google_changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc "Returns the user with `email`, or `nil`."
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.downcase(email))
  end

  @doc "Starts a session for `user`: returns the raw token for the session cookie."
  def generate_user_session_token(%User{} = user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc "Returns the user of a session `token` that has not expired, or `nil`."
  def get_user_by_session_token(token) when is_binary(token) do
    token |> UserToken.verify_session_token_query() |> Repo.one()
  end

  def get_user_by_session_token(_token), do: nil

  @doc "Ends the session of `token`."
  def delete_user_session_token(token) when is_binary(token) do
    token |> UserToken.by_token_query() |> Repo.delete_all()
    :ok
  end

  def delete_user_session_token(_token), do: :ok
end
