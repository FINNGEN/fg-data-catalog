defmodule FGDataCatalogWeb.DatasetFormLiveTest do
  # NOTE(Claude 2026-11-04): tests of the "new dataset" form page.
  # NOTE(Claude-Opus-5.5 2026-11-26): the page creates a Draft as soon as
  # the form is valid, and becomes its edit page; no Submit, no Discard.
  # Not async: these tests read and then write (the draft autosave) inside one
  # sandbox transaction, and SQLite fails with "Database busy" when another
  # test holds the write lock at that moment.
  use FGDataCatalogWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import FGDataCatalog.CatalogFixtures

  alias FGDataCatalog.Catalog
  alias FGDataCatalog.Catalog.DatasetVersion
  alias FGDataCatalog.Repo

  # NOTE(Claude 2026-11-16): the signed-in user (`:editor`, see
  # `FGDataCatalogWeb.ConnCase`) owns the autosaved new dataset:
  # `user_id(:editor)`.

  @version_params %{
    "version" => "R14",
    "release_date" => "2026-03-13",
    "lead" => "Jane Doe",
    "access_type" => "red",
    "data_quality" => %{"documented" => "yes", "in_one_piece" => "no", "quality_checked" => ""},
    "tags" => "Phenotype, Longitudinal",
    "environments" => "Sandbox",
    "formats" => "Flat file, BigQuery DB table",
    "modalities" => "Text, Genes",
    "coverage_start" => "2013",
    "coverage_end" => "2025",
    "cohort_size" => "500000"
  }

  defp open_new_row(conn) do
    {:ok, view, _html} = live(conn, ~p"/datasets/new")
    view
  end

  # NOTE(Claude-Opus-5.5 2026-11-26): fills the required fields, which creates
  # the draft; returns its version.
  defp create_draft(view, name, version_params \\ %{}) do
    view
    |> form("#edit-form",
      edit_dataset: %{name: name},
      edit_version:
        Map.merge(%{"version" => "R1", "release_date" => "2026-01-01"}, version_params)
    )
    |> render_change()

    [version] = Repo.all(DatasetVersion)
    assert_patch(view, ~p"/versions/#{version.id}/edit")
    version
  end

  test "the add link opens the form page, the back link leaves it", %{conn: conn} do
    {:ok, index, _html} = live(conn, ~p"/")

    {:ok, view, _html} =
      index
      |> element("#add-dataset")
      |> render_click()
      |> follow_redirect(conn, ~p"/datasets/new")

    assert has_element?(view, "#form-title", "Add missing dataset")
    assert has_element?(view, "#edit-form[phx-change='validate']")
    assert has_element?(view, "#edit-form input[name='edit_dataset[name]'][autofocus]")
    assert has_element?(view, "#edit-form input[name='edit_version[lead]']")

    {:ok, index, _html} =
      view |> element("#back-to-catalog") |> render_click() |> follow_redirect(conn, ~p"/")

    assert has_element?(index, ".catalog-table")
  end

  # NOTE(Claude 2026-11-12): the status and buttons sit apart from the fields,
  # in a footer kept in view by CSS.
  test "before the draft exists: Publish waits, Delete draft, no Submit", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/datasets/new")

    assert has_element?(
             view,
             "#edit-form > #edit-form-footer .draft-status",
             "open the other fields"
           )

    assert has_element?(view, "#edit-form-footer #edit-publish[disabled]")
    assert has_element?(view, "#edit-form-footer #edit-delete")
    refute has_element?(view, "#edit-form button[type='submit']")
    refute has_element?(view, "#edit-state")
  end

  # NOTE(Claude 2026-11-06): the autosave is the signed-in user's, not the
  # browser's: another sign-in of the same user finds it.
  test "the autosave follows the user to another browser", %{conn: conn} do
    view = open_new_row(conn)
    view |> form("#edit-form", edit_dataset: %{name: "From the laptop"}) |> render_change()

    {:ok, view, _html} = live(log_in(build_conn(), :editor), ~p"/datasets/new")

    assert has_element?(
             view,
             "#edit-form input[name='edit_dataset[name]'][value='From the laptop']"
           )
  end

  test "shows validation errors as the user types", %{conn: conn} do
    view = open_new_row(conn)

    view
    |> form("#edit-form", edit_dataset: %{name: ""}, edit_version: %{cohort_size: "-1"})
    |> render_change()

    assert has_element?(view, "#edit-form", "can't be blank")
    assert has_element?(view, "#edit-form", "must be greater than 0")
    assert Repo.all(DatasetVersion) == []
  end

  test "keeps the required fields until the draft exists, and restores them", %{conn: conn} do
    view = open_new_row(conn)
    view |> form("#edit-form", edit_dataset: %{name: "Half done"}) |> render_change()

    # NOTE(Claude-Opus-5.5 2026-11-26): stored in the former form's shape (see
    # `DatasetLive.Form.save_draft/2`), which the earlier releases read too.
    assert %{"name" => "Half done", "versions" => %{"0" => _}} =
             Catalog.get_dataset_draft_params(user_id(:editor))

    assert Repo.all(DatasetVersion) == []

    # NOTE(Claude 2026-11-04): a new LiveView with the same session, as after
    # closing and reopening the page.
    {:ok, index, _html} = live(conn, ~p"/")
    assert has_element?(index, "#add-dataset", "Continue adding dataset")
    {:ok, view, _html} = live(conn, ~p"/datasets/new")
    assert has_element?(view, "#edit-form input[name='edit_dataset[name]'][value='Half done']")

    # Another user does not see it.
    {:ok, other, _html} = live(log_in(build_conn(), "other@finngen.fi"), ~p"/datasets/new")
    refute has_element?(other, "#edit-form input[value='Half done']")
  end

  # NOTE(Claude-Opus-5.5 2026-11-26): the optional fields are disabled until
  # the draft exists, so nothing but the required fields can be lost.
  test "locks the optional fields until the draft exists", %{conn: conn} do
    view = open_new_row(conn)

    assert has_element?(view, "fieldset#description-field[disabled]")
    assert has_element?(view, "fieldset#optional-fields[disabled]")
    assert has_element?(view, "#optional-fields-note")
    refute has_element?(view, "input[name='edit_dataset[name]'][disabled]")
    refute has_element?(view, "fieldset[disabled] input[name='edit_version[version]']")
    refute has_element?(view, "fieldset[disabled] input[name='edit_version[release_date]']")

    create_draft(view, "Unlocked")

    refute has_element?(view, "fieldset[disabled]")
    refute has_element?(view, "#optional-fields-note")
  end

  # NOTE(Claude-Opus-5.5 2026-11-26): a browser does not send the disabled
  # fields: the autosave's values are kept under the fields it sends.
  test "an autosave's optional values are shown, locked, and kept in the draft", %{conn: conn} do
    {:ok, _} =
      Catalog.save_dataset_draft(user_id(:editor), %{
        "name" => "Restored",
        "description" => "Some words",
        "versions" => %{"0" => %{"tags" => "A, B", "lead" => "Jo"}}
      })

    {:ok, view, _html} = live(conn, ~p"/datasets/new")
    assert has_element?(view, "fieldset[disabled] input[name='edit_version[lead]'][value='Jo']")

    render_change(view, "validate", %{
      "edit_dataset" => %{"name" => "Restored"},
      "edit_version" => %{"version" => "R1", "release_date" => "2026-01-01"}
    })

    [version] = Repo.all(DatasetVersion) |> Repo.preload(:dataset)
    assert_patch(view, ~p"/versions/#{version.id}/edit")
    assert %{lead: "Jo", tags: ["A", "B"]} = version
    assert version.dataset.description == "Some words"
  end

  # NOTE(Claude-Opus-5.5 2026-11-26): saved by the former form, before
  # 2026-11-26, with its params.
  test "restores an autosave of the former new dataset form", %{conn: conn} do
    {:ok, _} =
      Catalog.save_dataset_draft(user_id(:editor), %{
        "name" => "Old autosave",
        "versions" => %{"0" => %{"lead" => "Jo"}}
      })

    {:ok, view, _html} = live(conn, ~p"/datasets/new")
    assert has_element?(view, "#edit-form input[name='edit_dataset[name]'][value='Old autosave']")
    assert has_element?(view, "#edit-form input[name='edit_version[lead]'][value='Jo']")
  end

  test "creates a Draft once the form is valid, and becomes its edit page", %{conn: conn} do
    view = open_new_row(conn)

    version_params =
      Map.merge(@version_params, %{
        "doc_links" => %{"0" => %{"label" => "README", "url" => "https://example.org/readme"}},
        "data_dictionary_csv" => "FINNGENID,Id",
        "yearly_counts_csv" => "2013,10\n2025,20"
      })

    render_change(view, "validate", %{
      "edit_dataset" => %{
        "name" => "Kanta lab values",
        "description" => "Laboratory test results"
      },
      "edit_version" => version_params
    })

    assert [%{id: id, dataset_id: dataset_id} = version] = Repo.all(DatasetVersion)
    assert_patch(view, ~p"/versions/#{id}/edit")

    assert version.state == :draft
    assert version.owning_editor_id == user_id(:editor)
    assert Catalog.get_dataset_draft_params(user_id(:editor)) == nil

    assert has_element?(view, "#form-title", "Edit Kanta lab values R14")
    assert has_element?(view, "#status-#{id}", "My draft")
    assert has_element?(view, "#edit-status", "Saved.")
    assert has_element?(view, "#edit-publish:not([disabled])")
    assert has_element?(view, "#edit-delete")

    # NOTE(Claude 2026-11-05): stored sorted, not in the order typed.
    assert version.tags == ["Longitudinal", "Phenotype"]
    assert version.formats == ["BigQuery DB table", "Flat file"]
    assert version.modalities == ["Genes", "Text"]
    # NOTE(Claude 2026-11-16): Unknown (an empty value) is not stored.
    assert version.data_quality == %{"documented" => "yes", "in_one_piece" => "no"}
    assert length(version.data_dictionary) == 1
    assert Enum.map(version.yearly_counts, & &1.count) == [10, 20]

    # NOTE(Claude-Opus-5.5 2026-11-26): every editor sees it in the catalog;
    # visitors do not.
    assert [%{id: ^dataset_id}] = Catalog.list_datasets(scope_fixture(:editor))
    assert [%{id: ^dataset_id}] = Catalog.list_datasets(scope_fixture(:other_editor))
    assert Catalog.list_published_datasets() == []

    # NOTE(Claude-Opus-5.5 2026-11-26): the next changes are saved at once, as on any edit page.
    view |> form("#edit-form", edit_version: %{lead: "John Doe"}) |> render_change()
    assert Repo.get!(DatasetVersion, id).lead == "John Doe"

    FGDataCatalog.DataCase.assert_replayable()
  end

  test "a taken name creates nothing, and keeps the autosave", %{conn: conn} do
    dataset = dataset_fixture(%{name: "Taken"})
    version_fixture(dataset)
    view = open_new_row(conn)

    view
    |> form("#edit-form",
      edit_dataset: %{name: "Taken"},
      edit_version: %{version: "R1", release_date: "2026-01-01"}
    )
    |> render_change()

    assert has_element?(view, "#edit-form", "has already been taken")
    assert has_element?(view, "#name-holder")
    assert [_one] = Repo.all(DatasetVersion)

    assert %{"name" => "Taken"} = Catalog.get_dataset_draft_params(user_id(:editor))
  end

  # NOTE(Claude Opus 5.5 2026-11-17): only the name, version and release date
  # are required, and marked so; the other fields are neither marked nor
  # labelled "optional".
  test "marks the required fields only", %{conn: conn} do
    view = open_new_row(conn)

    assert has_element?(view, "#edit-form-required-note")

    for name <- ["edit_dataset[name]", "edit_version[version]", "edit_version[release_date]"] do
      assert has_element?(view, "#edit-form input[name='#{name}'][aria-required='true']")
      refute has_element?(view, "#edit-form input[name='#{name}'][required]")
    end

    for name <- ["edit_dataset[description]", "edit_version[lead]", "edit_version[cohort_size]"] do
      refute has_element?(view, "#edit-form input[name='#{name}'][aria-required]")
    end

    refute has_element?(view, "#edit-form select[aria-required]")
    refute has_element?(view, "#edit-form .field-label", "optional")
  end

  test "creates a draft with the required fields only", %{conn: conn} do
    view = open_new_row(conn)
    version = create_draft(view, "Minimal")

    assert %{version: "R1", access_type: nil, cohort_size: nil, state: :draft} = version
  end

  test "Delete draft, before the draft exists, forgets the autosave", %{conn: conn} do
    view = open_new_row(conn)
    view |> form("#edit-form", edit_dataset: %{name: "Never mind"}) |> render_change()
    assert Catalog.get_dataset_draft_params(user_id(:editor))

    assert {:ok, _index, _html} =
             view |> element("#edit-delete") |> render_click() |> follow_redirect(conn, ~p"/")

    assert Catalog.get_dataset_draft_params(user_id(:editor)) == nil
  end

  test "Delete draft, once it exists, deletes it and its dataset", %{conn: conn} do
    view = open_new_row(conn)
    create_draft(view, "Short-lived")

    {:ok, index, _html} =
      view |> element("#edit-delete") |> render_click() |> follow_redirect(conn, ~p"/")

    assert has_element?(index, "#flash-info", "Deleted the draft Short-lived R1")
    assert Repo.all(DatasetVersion) == []
    assert Catalog.list_datasets(scope_fixture(:editor)) == []
    FGDataCatalog.DataCase.assert_replayable()
  end

  test "Publish from the page makes the draft Live", %{conn: conn} do
    view = open_new_row(conn)
    version = create_draft(view, "Ready")

    {:ok, index, _html} =
      view |> element("#edit-publish") |> render_click() |> follow_redirect(conn, ~p"/")

    assert has_element?(index, "#flash-info", "Published Ready R1")
    assert Repo.get!(DatasetVersion, version.id).state == :published
  end
end
