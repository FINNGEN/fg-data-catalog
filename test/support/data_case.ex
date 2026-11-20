defmodule FGDataCatalog.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use FGDataCatalog.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias FGDataCatalog.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import FGDataCatalog.DataCase
      import FGDataCatalog.AccountsFixtures
    end
  end

  setup tags do
    FGDataCatalog.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(FGDataCatalog.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  Asserts that the changelog accounts for every row of the catalog tables:
  replaying all changes forward from an empty database gives the current
  tables, and replaying them backward from the current tables gives an empty
  database. Fails if a write bypassed `FGDataCatalog.Changelog`.
  """
  # NOTE(Claude 2026-11-03): the test database starts empty, inside the sandbox.
  def assert_replayable do
    alias FGDataCatalog.Changelog
    alias FGDataCatalog.Changelog.Replay

    changes = Changelog.list_changes()
    snapshot = Changelog.snapshot()
    ExUnit.Assertions.assert(Replay.forward(Changelog.empty_snapshot(), changes) == snapshot)
    ExUnit.Assertions.assert(Replay.backward(snapshot, changes) == Changelog.empty_snapshot())
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
