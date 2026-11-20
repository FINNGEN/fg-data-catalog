defmodule FGDataCatalogWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use FGDataCatalogWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint FGDataCatalogWeb.Endpoint

      use FGDataCatalogWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import FGDataCatalogWeb.ConnCase
      import FGDataCatalog.AccountsFixtures
    end
  end

  # NOTE(Claude 2026-11-16): the conn is signed in as `:editor` unless the
  # test is tagged `role: :other_editor` (another editor) or `role: :visitor`
  # (not signed in), as `@tag`, `@describetag` or `@moduletag`.
  # Async tests start as visitors: signing in writes to the database, which
  # SQLite does not allow from concurrent tests ("Database busy").
  setup tags do
    FGDataCatalog.DataCase.setup_sandbox(tags)
    conn = Phoenix.ConnTest.build_conn()

    case Map.get(tags, :role, if(tags[:async], do: :visitor, else: :editor)) do
      :visitor -> {:ok, conn: conn}
      role -> {:ok, conn: log_in(conn, role)}
    end
  end

  @doc """
  Signs `conn` in as `who`: `:editor` (editor@finngen.fi), `:other_editor`
  (other-editor@finngen.fi) or any email; every user is an editor.
  """
  def log_in(conn, who) do
    user = FGDataCatalog.AccountsFixtures.user_fixture(who)
    token = FGDataCatalog.Accounts.generate_user_session_token(user)
    Plug.Test.init_test_session(conn, %{"user_token" => token})
  end
end
