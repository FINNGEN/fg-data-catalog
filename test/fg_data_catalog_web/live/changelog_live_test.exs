defmodule FGDataCatalogWeb.ChangelogLiveTest do
  # NOTE(Claude 2026-11-16): the changelog page, for editors. Not async: it
  # receives live-update broadcasts.
  use FGDataCatalogWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import FGDataCatalog.CatalogFixtures

  alias FGDataCatalog.Catalog

  setup do
    dataset = dataset_fixture(%{name: "Logged data"}, actor: "session:abc")
    version = version_fixture(dataset, %{version: "R1"}, actor: "session:abc")
    %{version: version}
  end

  test "lists change sets with their changes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/changelog")
    assert has_element?(view, "#changes tr.change .row-ref", "Versions")
    assert has_element?(view, "#changes-#{last_change_id()}")
    assert has_element?(view, "#changes tr.first-of-set td", "session:abc")
    assert has_element?(view, "#changelog-table th", "Operation")
  end

  test "shows new changes live, with the old and new value of an update", %{
    conn: conn,
    version: version
  } do
    {:ok, view, _html} = live(conn, ~p"/changelog")
    {:ok, _} = Catalog.archive_version(scope_fixture(:other_editor), version)
    assert has_element?(view, "#changes tr.first-of-set td", "archive version")
    assert has_element?(view, "#changes .change-diff dt", "archived_at")
    assert has_element?(view, "#changes .change-diff dt", "state")
  end

  defp last_change_id, do: FGDataCatalog.Changelog.last_change_id()

  # NOTE(Claude 2026-11-06): rows are named after their dataset (and version),
  # and the list can be filtered by table, row and actor.
  test "names rows after their dataset and version", %{conn: conn, version: version} do
    {:ok, view, _html} = live(conn, ~p"/changelog")
    assert has_element?(view, "#changes .row-filter-link", "Logged data R1")
    assert has_element?(view, "#changes .row-filter-link", "Logged data")

    # A renamed dataset shows its current name.
    {:ok, _} =
      Catalog.update_dataset_row(
        FGDataCatalog.Repo.get!(FGDataCatalog.Catalog.Dataset, version.dataset_id),
        %{name: "Renamed"},
        version,
        %{},
        scope: scope_fixture(:editor)
      )

    {:ok, view, _html} = live(conn, ~p"/changelog")
    assert has_element?(view, "#changes .row-filter-link", "Renamed R1")
  end

  test "filters by row, from a row's name", %{conn: conn, version: version} do
    version_fixture(dataset_fixture(%{name: "Other"}), %{version: "X"})

    {:ok, view, _html} = live(conn, ~p"/changelog")

    view
    |> element("#changes-#{hd(change_ids("dataset_versions", version.id))} .row-filter-link")
    |> render_click()

    assert_patch(view, ~p"/changelog?#{[row: version.id, table: "dataset_versions"]}")
    assert has_element?(view, "#row-filter", "Logged data R1")
    assert has_element?(view, "#changes .row-filter-link", "Logged data R1")
    refute has_element?(view, "#changes .row-filter-link", "Other X")

    view |> element("#clear-row-filter") |> render_click()
    assert_patch(view, ~p"/changelog?table=dataset_versions")
    assert has_element?(view, "#changes .row-filter-link", "Other X")
    refute has_element?(view, "#changes .row-filter-link", ~r/^\s*Logged data\s*$/)
  end

  # NOTE(Claude Opus 5.5 2026-11-19): a version's History link shows the
  # changes of everything its catalog row shows: the version's and its
  # dataset's, not its other versions'.
  describe "a version's history" do
    setup %{version: version} do
      dataset = FGDataCatalog.Repo.get!(FGDataCatalog.Catalog.Dataset, version.dataset_id)
      sibling = version_fixture(dataset, %{version: "R2"})
      other = version_fixture(dataset_fixture(%{name: "Other"}), %{version: "X"})

      {:ok, _} =
        Catalog.update_dataset_row(dataset, %{description: "Edited"}, version, %{},
          scope: scope_fixture(:editor)
        )

      %{dataset: dataset, sibling: sibling, other: other}
    end

    test "lists the version's and its dataset's changes, from its History link", %{
      conn: conn,
      version: version,
      dataset: dataset,
      sibling: sibling,
      other: other
    } do
      {:ok, index, _html} = live(conn, ~p"/")

      {:ok, view, _html} =
        index
        |> element("#history-version-#{version.id}")
        |> render_click()
        |> follow_redirect(conn, ~p"/changelog?#{[version: version.id]}")

      assert has_element?(view, "#row-filter", "Logged data R1")
      refute has_element?(view, "#changelog-filters select[name='table']")

      shown = change_ids("dataset_versions", version.id) ++ change_ids("datasets", dataset.id)
      # The dataset's insert and description edit, and the version's insert.
      assert length(shown) >= 3
      for id <- shown, do: assert(has_element?(view, "#changes-#{id}"))

      hidden =
        change_ids("dataset_versions", sibling.id) ++
          change_ids("dataset_versions", other.id) ++
          change_ids("datasets", other.dataset_id)

      for id <- hidden, do: refute(has_element?(view, "#changes-#{id}"))

      view |> element("#clear-row-filter") |> render_click()
      assert_patch(view, ~p"/changelog")
      assert has_element?(view, "#changes-#{hd(hidden)}")
    end

    test "of a deleted version still lists its and its dataset's changes", %{
      conn: conn,
      dataset: dataset,
      sibling: sibling
    } do
      [insert | _] = change_ids("dataset_versions", sibling.id)
      set_id = FGDataCatalog.Repo.get!(FGDataCatalog.Changelog.Change, insert).change_set_id
      {:ok, _} = Catalog.revert_change_set(scope_fixture(:editor), set_id)
      refute FGDataCatalog.Repo.get(FGDataCatalog.Catalog.DatasetVersion, sibling.id)

      {:ok, view, _html} = live(conn, ~p"/changelog?#{[version: sibling.id]}")
      assert has_element?(view, "#row-filter", "Logged data R2")

      # Its insert and its delete (by the revert), and the dataset's changes.
      shown = change_ids("dataset_versions", sibling.id) ++ change_ids("datasets", dataset.id)
      assert length(change_ids("dataset_versions", sibling.id)) == 2
      for id <- shown, do: assert(has_element?(view, "#changes-#{id}"))
    end

    test "combines with the actor filter", %{conn: conn, version: version, dataset: dataset} do
      {:ok, view, _html} =
        live(conn, ~p"/changelog?#{[version: version.id, actor: "session:abc"]}")

      [dataset_insert, description_edit] = change_ids("datasets", dataset.id)
      assert has_element?(view, "#changes-#{dataset_insert}")
      assert has_element?(view, "#changes-#{hd(change_ids("dataset_versions", version.id))}")
      refute has_element?(view, "#changes-#{description_edit}")

      # Choosing another actor keeps the version filter.
      view |> form("#changelog-filters", %{"actor" => "editor@finngen.fi"}) |> render_change()
      assert_patch(view, ~p"/changelog?#{[actor: "editor@finngen.fi", version: version.id]}")
      assert has_element?(view, "#changes-#{description_edit}")
    end

    test "replaces the table and row filters", %{conn: conn, version: version, other: other} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/changelog?#{[version: version.id, table: "datasets", row: other.dataset_id]}"
        )

      assert has_element?(view, "#changes-#{hd(change_ids("dataset_versions", version.id))}")
      refute has_element?(view, "#changes-#{hd(change_ids("datasets", other.dataset_id))}")
    end

    test "ignores a malformed version", %{conn: conn, other: other} do
      {:ok, view, _html} = live(conn, ~p"/changelog?version=abc")
      refute has_element?(view, "#row-filter")
      refute has_element?(view, "#clear-filters")
      assert has_element?(view, "#changes-#{hd(change_ids("datasets", other.dataset_id))}")
    end

    test "shows new changes of the version's dataset live", %{
      conn: conn,
      version: version,
      dataset: dataset,
      sibling: sibling
    } do
      {:ok, view, _html} = live(conn, ~p"/changelog?#{[version: version.id]}")

      {:ok, _} =
        Catalog.update_dataset_row(dataset, %{description: "Again"}, sibling, %{lead: "Z"},
          scope: scope_fixture(:other_editor)
        )

      assert has_element?(view, "#changes-#{List.last(change_ids("datasets", dataset.id))}")

      refute has_element?(
               view,
               "#changes-#{List.last(change_ids("dataset_versions", sibling.id))}"
             )
    end
  end

  defp change_ids(table, record_id) do
    FGDataCatalog.Repo.all(
      from c in FGDataCatalog.Changelog.Change,
        where: c.table_name == ^table and c.record_id == ^record_id,
        order_by: c.id,
        select: c.id
    )
  end

  test "filters by table and actor from the form", %{conn: conn} do
    _ = dataset_fixture(%{name: "By someone else"}, actor: "session:xyz")
    {:ok, view, _html} = live(conn, ~p"/changelog")

    view |> form("#changelog-filters", %{"actor" => "session:xyz"}) |> render_change()
    assert_patch(view, ~p"/changelog?#{[actor: "session:xyz"]}")
    assert has_element?(view, "#changes .row-filter-link", "By someone else")
    refute has_element?(view, "#changes .row-filter-link", "Logged data")

    view
    |> form("#changelog-filters", %{"actor" => "session:xyz", "table" => "dataset_versions"})
    |> render_change()

    assert has_element?(view, "#changelog-empty", "No changes match")

    view |> element("#clear-filters") |> render_click()
    assert_patch(view, ~p"/changelog")
    assert has_element?(view, "#changes .row-filter-link", "Logged data")
  end

  # NOTE(Claude 2026-11-06): Revert undoes a change set as a new one.
  test "Revert undoes a change set, or says why it cannot", %{conn: conn, version: version} do
    {:ok, _} = Catalog.archive_version(scope_fixture(:other_editor), version)
    archive_set = FGDataCatalog.Repo.get!(FGDataCatalog.Catalog.DatasetVersion, version.id)
    assert archive_set.archived_at
    set_id = last_set_id()

    {:ok, view, _html} = live(conn, ~p"/changelog")
    assert has_element?(view, "#revert-set-#{set_id}[data-confirm*='its 1 change']")
    view |> element("#revert-set-#{set_id}") |> render_click()

    assert has_element?(view, "#flash-info", "Reverted change set ##{set_id}")

    assert %{state: :published, archived_at: nil} =
             FGDataCatalog.Repo.get!(FGDataCatalog.Catalog.DatasetVersion, version.id)

    assert has_element?(view, "#changes tr.first-of-set td", "revert change set ##{set_id}")

    # The same change set again: its row has changed since (it was reverted).
    view |> element("#revert-set-#{set_id}") |> render_click()
    assert has_element?(view, "#flash-error", "Logged data R1 has changed since")
  end

  defp last_set_id do
    FGDataCatalog.Repo.one(from s in FGDataCatalog.Changelog.ChangeSet, select: max(s.id))
  end

  test "live updates respect the filters", %{conn: conn, version: version} do
    {:ok, view, _html} = live(conn, ~p"/changelog?actor=nobody")
    {:ok, _} = Catalog.archive_version(scope_fixture(:other_editor), version)
    refute has_element?(view, "#changes tr.change")
  end

  test "is linked from the catalog for editors", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#changelog-link")
  end

  describe "for a visitor" do
    @describetag role: :visitor

    test "redirects and shows no link", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/changelog")
      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "#changelog-link")
    end
  end

  # NOTE(Claude Opus 5.5 2026-11-18): consecutive live edits of one field are
  # one row, reverted as one.
  describe "runs of live edits" do
    defp live_edit(version, attrs, who \\ :editor) do
      version = FGDataCatalog.Repo.get!(FGDataCatalog.Catalog.DatasetVersion, version.id)
      dataset = FGDataCatalog.Repo.get!(FGDataCatalog.Catalog.Dataset, version.dataset_id)

      {:ok, _} =
        Catalog.update_dataset_row(dataset, %{}, version, attrs, scope: scope_fixture(who))

      last_set_id()
    end

    test "are one row, reverted as one", %{conn: conn, version: version} do
      _ = live_edit(version, %{lead: "B"})
      _ = live_edit(version, %{lead: "BC"})
      last = live_edit(version, %{lead: "BCD"})

      {:ok, view, _html} = live(conn, ~p"/changelog")
      assert has_element?(view, "#changes tr.first-of-set .edit-run", "3 saves")
      assert has_element?(view, "#revert-set-#{last}[data-confirm*='the 3 saves']")
      assert has_element?(view, "#changes .change-diff dt", "lead")

      view |> element("#revert-set-#{last}") |> render_click()
      assert has_element?(view, "#flash-info", "Reverted 3 saves")

      assert FGDataCatalog.Repo.get!(FGDataCatalog.Catalog.DatasetVersion, version.id).lead ==
               version.lead
    end

    test "a new live edit joins the top row", %{conn: conn, version: version} do
      first = live_edit(version, %{lead: "B"})
      {:ok, view, _html} = live(conn, ~p"/changelog")
      assert has_element?(view, "#revert-set-#{first}")
      refute has_element?(view, ".edit-run")

      second = live_edit(version, %{lead: "BC"})
      assert has_element?(view, "#changes .edit-run", "2 saves")
      assert has_element?(view, "#revert-set-#{second}")
      refute has_element?(view, "#revert-set-#{first}")

      # One row fewer than changes: the two edits share one.
      rows = view |> render() |> LazyHTML.from_document() |> LazyHTML.query("#changes tr.change")
      assert Enum.count(rows) == length(FGDataCatalog.Changelog.list_recent_changes()) - 1
    end

    test "are split by a change set in between, even filtered out", %{
      conn: conn,
      version: version
    } do
      _ = live_edit(version, %{lead: "B"})
      _ = live_edit(version, %{locations: [%{value: "/data/x"}]}, :other_editor)
      _ = live_edit(version, %{lead: "BC"})

      {:ok, view, _html} = live(conn, ~p"/changelog?actor=editor@finngen.fi")
      refute has_element?(view, ".edit-run")
    end

    test "that change nothing in the end have no Revert", %{conn: conn, version: version} do
      _ = live_edit(version, %{lead: "B"})
      last = live_edit(version, %{lead: version.lead})

      {:ok, view, _html} = live(conn, ~p"/changelog")
      assert has_element?(view, "#changes .no-net-change")
      refute has_element?(view, "#revert-set-#{last}")
    end
  end
end
