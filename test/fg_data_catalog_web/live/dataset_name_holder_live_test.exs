defmodule FGDataCatalogWeb.DatasetNameHolderLiveTest do
  # NOTE(Claude 2026-11-06): the new dataset form says why a name is taken when
  # the dataset holding it is in the catalog, archived or not published yet.
  # Not async: the form autosaves (see DatasetFormLiveTest).
  use FGDataCatalogWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import FGDataCatalog.CatalogFixtures

  alias FGDataCatalog.Catalog

  defp type_name(conn, name) do
    {:ok, view, _html} = live(conn, ~p"/datasets/new")
    view |> form("#dataset-form", dataset: %{name: name}) |> render_change()
    view
  end

  test "a free name shows no note", %{conn: conn} do
    view = type_name(conn, "Brand new")
    refute has_element?(view, "#name-holder")
  end

  test "a listed dataset's name links to adding a version of it", %{conn: conn} do
    dataset = dataset_fixture(%{name: "Kanta lab values"})
    version_fixture(dataset)

    view = type_name(conn, " Kanta lab values ")

    assert has_element?(
             view,
             "#name-holder-add-version[href='/datasets/#{dataset.id}/versions/new']"
           )
  end

  # NOTE(Claude 2026-11-16): every editor gets the links, no longer admins only.
  test "an archived dataset's name: links to unarchive it or add a version, explained on Submit",
       %{conn: conn} do
    dataset = dataset_fixture(%{name: "Old one"})
    {:ok, _} = Catalog.archive_version(scope_fixture(:other_editor), version_fixture(dataset))

    view = type_name(conn, "Old one")
    assert has_element?(view, "#name-holder", "archived dataset")
    assert has_element?(view, "#name-holder-archive[href='/archive']")
    assert has_element?(view, "#name-holder-add-version")

    view |> form("#dataset-form") |> render_submit()
    assert has_element?(view, "#name-holder", "archived dataset")
  end

  # NOTE(Claude 2026-11-16): every editor sees every Draft: the dataset is in
  # the catalog for them.
  test "someone else's Draft dataset's name links to adding a version of it", %{conn: conn} do
    dataset = dataset_fixture(%{name: "Pending"})

    version_fixture(dataset, %{},
      state: :draft,
      owning_editor_id: user_id(:other_editor)
    )

    view = type_name(conn, "Pending")
    assert has_element?(view, "#name-holder-add-version")
  end
end
