defmodule FGDataCatalogWeb.DatasetFormLiveTest do
  # NOTE(Claude 2026-11-04): tests of the "new dataset" form page.
  # Not async: these tests read and then write (the draft autosave) inside one
  # sandbox transaction, and SQLite fails with "Database busy" when another
  # test holds the write lock at that moment.
  use FGDataCatalogWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FGDataCatalog.Accounts.Scope
  alias FGDataCatalog.Catalog

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

  test "the add link opens the form page, the back link leaves it", %{conn: conn} do
    {:ok, index, _html} = live(conn, ~p"/")

    {:ok, view, _html} =
      index
      |> element("#add-dataset")
      |> render_click()
      |> follow_redirect(conn, ~p"/datasets/new")

    assert has_element?(view, "#form-title", "Add missing dataset")
    assert has_element?(view, "#dataset-form[phx-change='validate'][phx-submit='save']")
    assert has_element?(view, "#dataset-form input[name='dataset[name]'][autofocus]")
    assert has_element?(view, "#dataset-form input[name='dataset[versions][0][lead]']")

    {:ok, index, _html} =
      view |> element("#back-to-catalog") |> render_click() |> follow_redirect(conn, ~p"/")

    assert has_element?(index, ".catalog-table")
  end

  # NOTE(Claude 2026-11-06): the draft is the signed-in user's, not the
  # browser's: another sign-in of the same user finds it.
  # NOTE(Claude 2026-11-12): the status and buttons sit apart from the fields,
  # in a footer kept in view by CSS.
  test "the draft status and buttons are in the form's footer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/datasets/new")

    assert has_element?(view, "#dataset-form > #dataset-form-footer .draft-status")
    assert has_element?(view, "#dataset-form-footer #submit-dataset")
    assert has_element?(view, "#dataset-form-footer #discard-dataset")
    refute has_element?(view, "#dataset-form .form-fields #submit-dataset")
  end

  test "the draft follows the user to another browser", %{conn: conn} do
    view = open_new_row(conn)
    view |> form("#dataset-form", dataset: %{name: "From the laptop"}) |> render_change()

    {:ok, view, _html} = live(log_in(build_conn(), :editor), ~p"/datasets/new")

    assert has_element?(
             view,
             "#dataset-form input[name='dataset[name]'][value='From the laptop']"
           )
  end

  test "shows validation errors as the user types", %{conn: conn} do
    view = open_new_row(conn)

    view
    |> form("#dataset-form", dataset: %{name: "", versions: %{"0" => %{cohort_size: "-1"}}})
    |> render_change()

    assert has_element?(view, "#dataset-form", "can't be blank")
    assert has_element?(view, "#dataset-form", "must be greater than 0")
  end

  test "saves the form as a draft and restores it on the next visit", %{conn: conn} do
    view = open_new_row(conn)

    view
    |> form("#dataset-form",
      dataset: %{
        name: "Half done",
        description: "Some words",
        versions: %{"0" => %{"tags" => "A, B", "lead" => "Jo"}}
      }
    )
    |> render_change()

    assert %{"name" => "Half done", "description" => "Some words"} =
             Catalog.get_dataset_draft_params(user_id(:editor))

    # NOTE(Claude 2026-11-04): a new LiveView with the same session, as after
    # closing and reopening the page. The form is not opened by itself.
    {:ok, index, _html} = live(conn, ~p"/")
    assert has_element?(index, "#add-dataset", "Continue adding dataset")
    {:ok, view, _html} = live(conn, ~p"/datasets/new")
    assert has_element?(view, "#dataset-form input[name='dataset[name]'][value='Half done']")

    assert has_element?(
             view,
             "#dataset-form input[name='dataset[description]'][value='Some words']"
           )

    # The list fields are shown trimmed.
    assert has_element?(view, "#dataset-form input[value='A,B']")
    # Incomplete, but no errors until it is edited again.
    refute has_element?(view, "#dataset-form", "can't be blank")

    # Another user does not see it.
    {:ok, other, _html} = live(log_in(build_conn(), "other@finngen.fi"), ~p"/datasets/new")
    refute has_element?(other, "#dataset-form input[value='Half done']")
  end

  test "adds and removes rows of a list field, and keeps them in the draft", %{conn: conn} do
    view = open_new_row(conn)
    link_input = "input[name='dataset[versions][0][doc_links][0][url]']"
    refute has_element?(view, link_input)

    render_change(view, "validate", %{
      "dataset" => %{"versions" => %{"0" => %{"doc_links_sort" => ["new"]}}}
    })

    assert has_element?(view, link_input)
    {:ok, restored, _html} = live(conn, ~p"/datasets/new")
    assert has_element?(restored, link_input)

    render_change(view, "validate", %{
      "dataset" => %{
        "versions" => %{
          "0" => %{"doc_links_sort" => ["0"], "doc_links_drop" => ["0"], "doc_links" => %{}}
        }
      }
    })

    refute has_element?(view, link_input)
  end

  test "keeps pasted CSV text as typed, with its errors, in the draft", %{conn: conn} do
    view = open_new_row(conn)
    textarea = "#dataset-form textarea[name='dataset[versions][0][yearly_counts_csv]']"
    assert has_element?(view, textarea)

    render_change(view, "validate", %{
      "dataset" => %{"versions" => %{"0" => %{"yearly_counts_csv" => "2013,10\n2014,x\n"}}}
    })

    assert has_element?(view, "#dataset-form", "line 2: count is invalid")
    {:ok, restored, _html} = live(conn, ~p"/datasets/new")
    assert has_element?(restored, textarea, "2014,x")
  end

  test "creates a dataset, shows it in the table and deletes the draft", %{conn: conn} do
    view = open_new_row(conn)
    render_change(view, "validate", %{"dataset" => %{"name" => "Kanta lab values"}})

    version =
      Map.merge(@version_params, %{
        "doc_links" => %{"0" => %{"label" => "README", "url" => "https://example.org/readme"}},
        "data_dictionary_csv" => "FINNGENID,Id",
        "yearly_counts_csv" => "2013,10\n2025,20"
      })

    {:ok, view, _html} =
      view
      |> element("#dataset-form")
      |> render_submit(%{
        "dataset" => %{
          "name" => "Kanta lab values",
          "description" => "Laboratory test results",
          "versions" => %{"0" => version}
        }
      })
      |> follow_redirect(conn, ~p"/")

    assert has_element?(view, "#add-dataset", "Add missing dataset")
    assert has_element?(view, "#flash-info", "Added Kanta lab values as a Draft")

    assert Catalog.list_published_datasets() == []

    assert [%{id: id, versions: [version]} = dataset] =
             Catalog.list_datasets(scope_fixture(:editor))

    assert version.state == :draft
    assert dataset.description == "Laboratory test results"
    assert has_element?(view, "#dataset-#{id}", "Kanta lab values")

    assert has_element?(
             view,
             "#version-#{version.id} th .dataset-description",
             "Laboratory test results"
           )

    assert has_element?(view, "#version-#{version.id}", "500,000")
    # NOTE(Claude 2026-11-05): stored sorted, not in the order typed.
    assert version.tags == ["Longitudinal", "Phenotype"]
    assert version.formats == ["BigQuery DB table", "Flat file"]
    assert version.modalities == ["Genes", "Text"]
    # NOTE(Claude 2026-11-16): Unknown (an empty value) is not stored.
    assert version.data_quality == %{"documented" => "yes", "in_one_piece" => "no"}
    assert length(version.data_dictionary) == 1
    assert Enum.map(version.yearly_counts, & &1.count) == [10, 20]

    assert Catalog.get_dataset_draft_params(user_id(:editor)) == nil
    FGDataCatalog.DataCase.assert_replayable()
  end

  test "keeps the form open, with errors, when saving fails", %{conn: conn} do
    view = open_new_row(conn)

    view
    |> element("#dataset-form")
    |> render_submit(%{
      "dataset" => %{"name" => "Incomplete", "versions" => %{"0" => %{"version" => "R1"}}}
    })

    assert has_element?(view, "#dataset-form", "can't be blank")
    assert Catalog.list_published_datasets() == []
    assert %{"name" => "Incomplete"} = Catalog.get_dataset_draft_params(user_id(:editor))
  end

  # NOTE(Claude Opus 5.5 2026-11-17): only the name, version and release date
  # are required, and marked so; the other fields are neither marked nor
  # labelled "optional".
  test "marks the required fields only", %{conn: conn} do
    view = open_new_row(conn)
    version = "dataset[versions][0]"

    assert has_element?(view, "#dataset-form-required-note")

    for name <- ["dataset[name]", "#{version}[version]", "#{version}[release_date]"] do
      assert has_element?(view, "#dataset-form input[name='#{name}'][aria-required='true']")
      refute has_element?(view, "#dataset-form input[name='#{name}'][required]")
    end

    for name <- ["dataset[description]", "#{version}[lead]", "#{version}[cohort_size]"] do
      refute has_element?(view, "#dataset-form input[name='#{name}'][aria-required]")
    end

    refute has_element?(view, "#dataset-form select[aria-required]")
    refute has_element?(view, "#dataset-form .field-label", "optional")
  end

  test "creates a dataset with the required fields only", %{conn: conn} do
    view = open_new_row(conn)

    view
    |> element("#dataset-form")
    |> render_submit(%{
      "dataset" => %{
        "name" => "Minimal",
        "versions" => %{"0" => %{"version" => "R1", "release_date" => "2026-01-01"}}
      }
    })

    assert [%{name: "Minimal", versions: [version]}] =
             Catalog.list_datasets(Scope.for_user(user_fixture(:editor)))

    assert %{version: "R1", access_type: nil, cohort_size: nil} = version
  end

  test "discarding closes the form and deletes the draft", %{conn: conn} do
    view = open_new_row(conn)
    render_change(view, "validate", %{"dataset" => %{"name" => "Never mind"}})
    assert Catalog.get_dataset_draft_params(user_id(:editor))

    assert {:ok, _index, _html} =
             view |> element("#discard-dataset") |> render_click() |> follow_redirect(conn, ~p"/")

    assert Catalog.get_dataset_draft_params(user_id(:editor)) == nil
  end
end
