defmodule FGDataCatalogWeb.RowActionsLiveTest do
  # NOTE(Claude Opus 5.5 2026-11-19): a catalog row's actions: the status badge
  # and Edit in the row, the others (Add version, History, Publish or
  # Unpublish, Archive or Delete draft) in the popover of its "…" button (`version_row/1`).
  # The permission rules themselves are tested in `DatasetStatusLiveTest`;
  # here, where each action is and which ones the popover lists.
  use FGDataCatalogWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import FGDataCatalog.CatalogFixtures

  # NOTE(Claude Opus 5.5 2026-11-19): a dataset with a Published version and a
  # newer Draft of `:editor`'s; the Draft is the current row for editors.
  setup do
    dataset = dataset_fixture(%{name: "Kanta lab values"})
    owner = user_id(:editor)

    published =
      version_fixture(dataset, %{version: "R14", release_date: ~D[2026-03-13]},
        owning_editor_id: owner
      )

    draft =
      version_fixture(dataset, %{version: "R15", release_date: ~D[2026-09-01]},
        state: :draft,
        owning_editor_id: owner
      )

    %{dataset: dataset, published: published, draft: draft}
  end

  # The ids of the controls in a row's actions popover, in order.
  defp menu_actions(view, version) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#actions-menu-#{version.id} li > [id]")
    |> LazyHTML.attribute("id")
  end

  defp current_row?(view, version),
    do: has_element?(view, "#version-#{version.id}.current-version")

  test "a visitor sees no actions button nor popover", %{published: published} do
    {:ok, view, _html} = live(build_conn(), ~p"/")

    assert has_element?(view, "#version-#{published.id}")
    refute has_element?(view, "#actions-#{published.id}")
    refute has_element?(view, "#actions-menu-#{published.id}")
    refute has_element?(view, "#history-version-#{published.id}")
    refute has_element?(view, "[popover]")
  end

  test "an editor's row: badge and Edit in the row, a button opening its popover",
       %{draft: draft, published: published} do
    {:ok, view, _html} = live(build_conn() |> log_in(:editor), ~p"/")

    for version <- [draft, published] do
      id = version.id
      assert has_element?(view, "#version-#{id} .row-actions #status-#{id}")
      assert has_element?(view, "#version-#{id} .row-actions > #edit-version-#{id}")

      assert has_element?(
               view,
               ~s(#version-#{id} .row-actions > button#actions-#{id}[popovertarget="actions-menu-#{id}"])
             )

      assert has_element?(view, ~s(#version-#{id} #actions-#{id}[aria-label][title]))
      assert has_element?(view, ~s(#actions-#{id} + #actions-menu-#{id}[popover="auto"]))
      # Not an ARIA menu: a plain list.
      refute has_element?(view, ~s(#actions-menu-#{id} [role="menu"]))
    end

    refute has_element?(view, ".icon-action-slot")
  end

  test "the aria-label names the version", %{draft: draft} do
    {:ok, view, _html} = live(build_conn() |> log_in(:editor), ~p"/")

    assert has_element?(
             view,
             ~s(#actions-#{draft.id}[aria-label="More actions for Kanta lab values R15"])
           )
  end

  # NOTE(Claude-Opus-5.5 2026-11-26): a draft is deleted, not archived.
  test "the owning editor: Publish or Delete their draft, Unpublish the Published version",
       %{dataset: dataset, draft: draft, published: published} do
    {:ok, view, _html} = live(build_conn() |> log_in(:editor), ~p"/")

    assert current_row?(view, draft)

    assert menu_actions(view, draft) == [
             "add-version-#{dataset.id}",
             "history-version-#{draft.id}",
             "publish-version-#{draft.id}",
             "delete-version-#{draft.id}"
           ]

    assert menu_actions(view, published) == [
             "history-version-#{published.id}",
             "unpublish-version-#{published.id}",
             "archive-version-#{published.id}"
           ]
  end

  # NOTE(Claude-Opus-5.5 2026-11-26): a Draft is every editor's.
  test "another editor: the same actions on a Draft they do not own",
       %{dataset: dataset, draft: draft, published: published} do
    {:ok, view, _html} = live(build_conn() |> log_in(:other_editor), ~p"/")

    assert has_element?(view, "#edit-version-#{draft.id}")
    assert has_element?(view, "#edit-version-#{published.id}")

    assert menu_actions(view, draft) == [
             "add-version-#{dataset.id}",
             "history-version-#{draft.id}",
             "publish-version-#{draft.id}",
             "delete-version-#{draft.id}"
           ]

    assert menu_actions(view, published) == [
             "history-version-#{published.id}",
             "unpublish-version-#{published.id}",
             "archive-version-#{published.id}"
           ]
  end

  test "Delete draft asks first", %{draft: draft} do
    {:ok, view, _html} = live(build_conn() |> log_in(:editor), ~p"/")
    assert has_element?(view, "#delete-version-#{draft.id}[data-confirm]")
  end

  test "Add version only in the current row's popover",
       %{dataset: dataset, draft: draft, published: published} do
    {:ok, view, _html} = live(build_conn() |> log_in(:editor), ~p"/")

    assert has_element?(view, "#actions-menu-#{draft.id} #add-version-#{dataset.id}")
    refute has_element?(view, "#actions-menu-#{published.id} .add-version")
    refute has_element?(view, "#version-#{published.id} .add-version")
  end

  describe "the result of an action, for `.CatalogTable`" do
    test "a success is pushed", %{draft: draft} do
      {:ok, view, _html} = live(build_conn() |> log_in(:editor), ~p"/")

      view |> element("#publish-version-#{draft.id}") |> render_click()

      id = to_string(draft.id)
      assert_push_event(view, "row_action", %{id: ^id, ok: true})
    end

    test "a failure is pushed", %{published: published} do
      {:ok, view, _html} = live(build_conn() |> log_in(:editor), ~p"/")

      # As a page rendered before the version was published would send it.
      render_hook(view, "publish", %{"id" => to_string(published.id)})

      id = to_string(published.id)
      assert_push_event(view, "row_action", %{id: ^id, ok: false})
    end
  end

  test "the table can take the focus from the hook" do
    {:ok, view, _html} = live(build_conn() |> log_in(:editor), ~p"/")

    assert has_element?(view, ~s(#catalog-table[tabindex="-1"]))
  end
end
