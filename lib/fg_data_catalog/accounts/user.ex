defmodule FGDataCatalog.Accounts.User do
  @moduledoc """
  A person who signed in with their Google `@finngen.fi` account.

  NOTE(Claude 2026-11-16): no password: Google vouches for the email. Every
  user is an editor (see `FGDataCatalog.Accounts.Scope`); there are no admins.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :name, :string
    field :google_sub, :string

    timestamps(type: :utc_datetime)
  end

  @doc "A changeset from the claims Google vouched for, never from a form."
  def google_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :google_sub])
    |> validate_required([:email, :google_sub])
    |> update_change(:email, &String.downcase/1)
    |> unique_constraint(:email)
    |> unique_constraint(:google_sub)
  end
end
