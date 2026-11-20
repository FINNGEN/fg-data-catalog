defmodule FGDataCatalog.AccountsFixtures do
  @moduledoc """
  NOTE(Claude 2026-11-16): test users and their scopes. Every user is an
  editor: `:editor` is editor@finngen.fi, `:other_editor` is
  other-editor@finngen.fi; any other email is an editor too.
  """

  alias FGDataCatalog.Accounts
  alias FGDataCatalog.Accounts.Scope

  @doc "The user `who`, created on first use."
  def user_fixture(:editor), do: user_fixture("editor@finngen.fi")
  def user_fixture(:other_editor), do: user_fixture("other-editor@finngen.fi")

  def user_fixture(email) when is_binary(email) do
    {:ok, user} = Accounts.upsert_google_user(%{sub: "test:" <> email, email: email})
    user
  end

  @doc "The scope of user `who`, for the `Catalog` functions that take one."
  def scope_fixture(who), do: who |> user_fixture() |> Scope.for_user()

  @doc "The changelog actor of user `who`: their email."
  def actor(:editor), do: "editor@finngen.fi"
  def actor(:other_editor), do: "other-editor@finngen.fi"
  def actor(email) when is_binary(email), do: email

  # NOTE(Claude 2026-11-16): a version's owning editor is a user id.
  @doc "The id of user `who` (created on first use): a version's owning editor."
  def user_id(who), do: user_fixture(who).id
end
