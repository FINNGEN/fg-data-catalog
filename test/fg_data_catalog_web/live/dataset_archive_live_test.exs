defmodule FGDataCatalogWeb.DatasetArchiveLiveTest do
  # NOTE(Claude 2026-11-05): archiving dataset versions and the archive page.
  # Not async: it receives live-update broadcasts.
  use FGDataCatalogWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import FGDataCatalog.CatalogFixtures
  import FGDataCatalog.DataCase, only: [assert_replayable: 0]

  alias FGDataCatalog.Catalog
  alias FGDataCatalog.Catalog.DatasetVersion
  alias FGDataCatalog.Repo

  setup do
    dataset = dataset_fixture(%{name: "Old data"})
    old = version_fixture(dataset, %{version: "R1", release_date: ~D[2025-01-01]})
    current = version_fixture(dataset, %{version: "R2", release_date: ~D[2026-01-01]})
    %{dataset: dataset, old: old, current: current}
  end

  test "an editor archives a version, it leaves the list but stays in the database",
       %{conn: conn, old: old, current: current} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#archive-version-#{old.id}")

    view |> element("#archive-version-#{old.id}") |> render_click()
    refute has_element?(view, "#version-#{old.id}")
    assert has_element?(view, "#version-#{current.id}")
    assert %{state: :archived, archived_at: %DateTime{}} = Repo.get!(DatasetVersion, old.id)
    assert_replayable()
  end

  test "the archive lists archived versions and unarchives them", %{conn: conn, old: old} do
    {:ok, _} = Catalog.archive_version(scope_fixture(:other_editor), old)

    {:ok, view, _html} = live(conn, ~p"/archive")
    assert has_element?(view, "#archived-version-#{old.id}")

    view |> element("#unarchive-version-#{old.id}") |> render_click()
    refute has_element?(view, "#archived-version-#{old.id}")
    assert has_element?(view, "#archive-empty")
    # NOTE(Claude 2026-11-16): back as a Draft owned by whoever unarchived it.
    assert %{state: :draft, archived_at: nil, owning_editor_id: owner} =
             Repo.get!(DatasetVersion, old.id)

    assert owner == user_id(:editor)

    {:ok, index, _html} = live(conn, ~p"/")
    assert has_element?(index, "#version-#{old.id}")
    assert has_element?(index, "#status-#{old.id}.status-draft")
    assert_replayable()
  end

  test "an archived version cannot be edited", %{conn: conn, old: old} do
    {:ok, _} = Catalog.archive_version(scope_fixture(:other_editor), old)
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/versions/#{old.id}/edit")
  end

  test "a dataset with every version archived leaves the list", %{
    conn: conn,
    dataset: dataset,
    old: old,
    current: current
  } do
    {:ok, _} = Catalog.archive_version(scope_fixture(:other_editor), old)
    {:ok, _} = Catalog.archive_version(scope_fixture(:other_editor), current)
    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#dataset-#{dataset.id}")
  end

  describe "for a visitor" do
    @describetag role: :visitor

    test "the archive page redirects and no Archive link is shown", %{conn: conn, old: old} do
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/archive")

      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "#archive-link")
      refute has_element?(view, "#archive-version-#{old.id}")
    end

    test "archiving is refused", %{old: old} do
      assert {:error, :unauthorized} = Catalog.archive_version(nil, old)
      assert {:error, :unauthorized} = Catalog.unarchive_version(nil, old)
    end

    test "an archive event is refused and the version stays", %{conn: conn, old: old} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "archive", %{"id" => to_string(old.id)})
      assert has_element?(view, "#version-#{old.id}")
      assert Repo.get!(DatasetVersion, old.id).state == :published
    end
  end

  test "archived_at and state cannot be set from attrs", %{dataset: dataset} do
    {:ok, version} =
      Catalog.create_dataset_version(
        dataset,
        valid_version_attrs(%{archived_at: DateTime.utc_now(), state: :archived})
      )

    assert %{archived_at: nil, state: :draft} = version
  end
end
