defmodule FGDataCatalogWeb.DatasetFormDisabledLiveTest do
  # NOTE(Claude 2026-11-06): a visitor (not signed in) may not add or edit.
  use FGDataCatalogWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FGDataCatalog.Catalog

  @moduletag role: :visitor

  # NOTE(Claude 2026-11-04): the links are hidden and the form pages are refused
  # server-side, even when reached without the links.
  test "the add and edit links are hidden and the forms are refused", %{conn: conn} do
    version =
      FGDataCatalog.CatalogFixtures.version_fixture(
        FGDataCatalog.CatalogFixtures.dataset_fixture()
      )

    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#add-dataset")
    refute has_element?(view, "a.edit-version")

    # NOTE(Claude 2026-11-04): the form pages send the user back with an error,
    # so no form event can reach them.
    for path <- [~p"/datasets/new", ~p"/versions/#{version.id}/edit"] do
      assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => _}}}} = live(conn, path)
    end

    assert [_one] = Catalog.list_published_datasets()
  end
end
