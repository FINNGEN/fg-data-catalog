defmodule FGDataCatalogWeb.KeyboardShortcutsLiveTest do
  # NOTE(Claude-Opus-5.5 2026-11-26): the catalog's keyboard shortcuts: / focuses
  # the search field, N opens "Add missing dataset" (editors only). The keys are
  # handled client side (`.CatalogTable`); here, only what they rely on: the
  # hook, the elements it finds, and their hints.
  use FGDataCatalogWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "an editor gets the / and N shortcuts, with their hints", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#catalog-table[phx-hook$='.CatalogTable']")
    assert has_element?(view, "#search-form input[type='search'][aria-keyshortcuts='/']")
    assert has_element?(view, "#search-shortcut[aria-hidden='true']", "/")

    assert has_element?(
             view,
             "#add-dataset[aria-keyshortcuts='N'][title='Add missing dataset (N)']"
           )

    assert has_element?(view, "#add-dataset kbd[aria-hidden='true']", "N")
  end

  # NOTE(Claude-Opus-5.5 2026-11-26): the first field is focused once the page
  # is mounted (`phx-mounted`), also after a live navigation, where
  # `autofocus` alone does nothing.
  test "N's page, Add missing dataset, focuses its first field", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    {:ok, form, _html} =
      view |> element("#add-dataset") |> render_click() |> follow_redirect(conn)

    assert has_element?(form, "#dataset-form input[name='dataset[name]'][autofocus]")
    assert has_element?(form, "#dataset-form input[name='dataset[name]'][phx-mounted*='focus']")
  end

  # NOTE(Claude-Opus-5.5 2026-11-26): Escape leaves the field, then the page
  # (client side, `.EscapeBack`): on the new dataset page only, not on the new
  # version and edit pages, where a typed value may be unsaved.
  test "only the new dataset page goes back on Escape, with its hint", %{conn: conn} do
    {:ok, new, _html} = live(conn, ~p"/datasets/new")

    assert has_element?(
             new,
             "#back-to-catalog[aria-keyshortcuts='Escape'] #back-shortcut[phx-hook='FGDataCatalogWeb.DatasetLive.Form.EscapeBack']"
           )

    assert has_element?(new, "#back-to-catalog kbd[aria-hidden='true']", "Esc")

    dataset = FGDataCatalog.CatalogFixtures.dataset_fixture(%{name: "Kanta lab values"})
    version = FGDataCatalog.CatalogFixtures.version_fixture(dataset, %{version: "R14"})

    for path <- [~p"/datasets/#{dataset.id}/versions/new", ~p"/versions/#{version.id}/edit"] do
      {:ok, view, _html} = live(conn, path)
      assert has_element?(view, "#back-to-catalog")
      refute has_element?(view, "#back-shortcut")
      refute has_element?(view, "#back-to-catalog kbd")
    end
  end

  describe "for a visitor" do
    @describetag role: :visitor

    test "only / is offered", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#catalog-table[data-can-edit='false']")
      assert has_element?(view, "#search-form input[type='search'][aria-keyshortcuts='/']")
      assert has_element?(view, "#search-shortcut")
      refute has_element?(view, "#add-dataset")
    end
  end
end
