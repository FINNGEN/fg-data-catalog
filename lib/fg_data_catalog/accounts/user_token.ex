defmodule FGDataCatalog.Accounts.UserToken do
  @moduledoc """
  A signed-in session.

  NOTE(Claude 2026-11-06): the raw token is random bytes kept in the session
  cookie; only its SHA-256 hash is stored, so a leaked database cannot be used
  to sign in. Deleting the row signs that session out.
  """
  use Ecto.Schema
  import Ecto.Query

  alias FGDataCatalog.Accounts.User

  @rand_size 32
  @session_validity_in_days 60

  schema "users_tokens" do
    field :token_hash, :binary
    field :context, :string
    belongs_to :user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def session_validity_in_days, do: @session_validity_in_days

  @doc "Returns `{token, user_token}`: the raw token, and the row to insert."
  def build_session_token(%User{} = user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %__MODULE__{token_hash: hash(token), context: "session", user_id: user.id}}
  end

  @doc "The query of the user of a session `token` that has not expired."
  def verify_session_token_query(token) do
    from t in by_token_query(token),
      join: u in assoc(t, :user),
      where: t.inserted_at > ago(@session_validity_in_days, "day"),
      select: u
  end

  def by_token_query(token) do
    from t in __MODULE__, where: t.token_hash == ^hash(token) and t.context == "session"
  end

  defp hash(token), do: :crypto.hash(:sha256, token)
end
