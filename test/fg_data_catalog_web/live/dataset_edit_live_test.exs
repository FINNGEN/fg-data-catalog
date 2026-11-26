defmodule FGDataCatalogWeb.DatasetEditLiveTest do
  # NOTE(Claude 2026-11-04): tests of editing an existing version on its edit
  # form page. Not async: the live-update test would receive other tests' broadcasts.
  use FGDataCatalogWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import FGDataCatalog.CatalogFixtures
  import FGDataCatalog.DataCase, only: [assert_replayable: 0]

  alias FGDataCatalog.Catalog.{Dataset, DatasetVersion}
  alias FGDataCatalog.Changelog.ChangeSet
  alias FGDataCatalog.Repo

  setup %{conn: conn} do
    dataset = dataset_fixture(%{name: "Kanta lab values"})
    old = version_fixture(dataset, %{version: "R13", release_date: ~D[2025-03-01]})
    current = version_fixture(dataset, %{version: "R14", release_date: ~D[2026-03-13]})
    %{conn: conn, dataset: dataset, old: old, current: current}
  end

  defp edit_row(conn, version) do
    {:ok, view, _html} = live(conn, ~p"/versions/#{version.id}/edit")
    view
  end

  defp last_change_set do
    Repo.one(from s in ChangeSet, order_by: [desc: s.id], limit: 1, preload: :changes)
  end

  test "Edit opens the version's form page, the back link leaves it", %{conn: conn} = ctx do
    {:ok, index, _html} = live(conn, ~p"/")
    assert has_element?(index, "#edit-version-#{ctx.old.id}")

    {:ok, view, _html} =
      index
      |> element("#edit-version-#{ctx.current.id}")
      |> render_click()
      |> follow_redirect(conn, ~p"/versions/#{ctx.current.id}/edit")

    assert has_element?(view, "#form-title", "Edit Kanta lab values R14")
    assert has_element?(view, "#edit-form[phx-change='validate']")
    assert has_element?(view, "#edit-form input[name='edit_dataset[name]'][autofocus]")
    assert has_element?(view, "#edit-form input[name='edit_version[lead]']")
    refute has_element?(view, ".catalog-table")

    {:ok, index, _html} =
      view |> element("#back-to-catalog") |> render_click() |> follow_redirect(conn, ~p"/")

    assert has_element?(index, ".catalog-table")
  end

  test "the Tags, Environments, Modality and Format fields suggest existing values",
       %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/versions/#{ctx.current.id}/edit")

    for field <- ~w(tags environments modalities formats) do
      assert has_element?(
               view,
               "#edit-form input[phx-hook$='.TokenSuggest'][data-suggestions][data-list$='#{field}-suggestions']"
             )

      assert has_element?(
               view,
               "#edit-form ul.suggestions[id$='#{field}-suggestions'][phx-update='ignore']"
             )
    end
  end

  test "an unknown version id shows an error and no form", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => _}}}} =
             live(conn, ~p"/versions/999999/edit")
  end

  test "each valid change is saved at once and logged", %{conn: conn} = ctx do
    view = edit_row(conn, ctx.current)

    view
    |> form("#edit-form", edit_version: %{lead: "Joe Bloggs", tags: "X, Y"})
    |> render_change()

    assert has_element?(view, "#edit-status", "Saved.")
    version = Repo.get!(DatasetVersion, ctx.current.id)
    assert version.lead == "Joe Bloggs"
    assert version.tags == ["X", "Y"]

    assert %ChangeSet{action: "edit row", actor: "editor@finngen.fi", changes: [change]} =
             last_change_set()

    assert change.old_values["lead"] == "Jane Doe"
    assert change.new_values["lead"] == "Joe Bloggs"

    {:ok, index, _html} =
      view |> element("#done-editing") |> render_click() |> follow_redirect(conn, ~p"/")

    assert has_element?(index, "#version-#{ctx.current.id}", "Joe Bloggs")
    assert_replayable()
  end

  # NOTE(Claude 2026-11-06): an invalid input is marked so, and points to its errors.
  test "an invalid input is described by its errors", %{conn: conn} = ctx do
    view = edit_row(conn, ctx.current)
    view |> form("#edit-form", edit_version: %{version: ""}) |> render_change()

    assert has_element?(
             view,
             "#edit_version_version[aria-invalid='true'][aria-describedby='edit_version_version-errors']"
           )

    assert has_element?(view, "#edit_version_version-errors .field-error", "can't be blank")
  end

  # NOTE(Claude 2026-11-09): the lead is optional: clearing it saves, and the
  # catalog shows a dash.
  test "the lead can be cleared", %{conn: conn} = ctx do
    view = edit_row(conn, ctx.current)
    view |> form("#edit-form", edit_version: %{lead: ""}) |> render_change()

    assert has_element?(view, "#edit-status", "Saved.")
    refute has_element?(view, "#edit_version_lead-errors")
    assert Repo.get!(DatasetVersion, ctx.current.id).lead == nil

    {:ok, index, _html} = live(conn, ~p"/")
    assert has_element?(index, "#version-#{ctx.current.id} td:last-child .no-value")

    assert_replayable()
  end

  # NOTE(Claude 2026-11-09): the actions sit in the row header, by the name;
  # there is no actions column.
  test "Archive is a button in the row header's actions", %{conn: conn} = ctx do
    {:ok, index, _html} = live(conn, ~p"/")

    assert has_element?(
             index,
             "#version-#{ctx.current.id} th .row-actions button#archive-version-#{ctx.current.id}"
           )

    refute has_element?(index, "thead th", "Actions")
    refute has_element?(index, "thead th", "Status")
  end

  # NOTE(Claude 2026-11-10): "OMOP-mapped", radio buttons (Yes, No, Unknown), shown
  # as an icon (unknown: a dash).
  test "the OMOP mapping is shown and can be changed", %{conn: conn} = ctx do
    cell = "#version-#{ctx.current.id} td.omop"
    {:ok, index, _html} = live(conn, ~p"/")
    assert has_element?(index, cell <> " .no-value")

    view = edit_row(conn, ctx.current)
    assert has_element?(view, "#edit_version_omop_integration_unknown[type='radio'][checked]")
    assert has_element?(view, "#edit_version_omop_integration_yes[type='radio']")
    assert has_element?(view, "#edit_version_omop_integration_no[type='radio']")
    refute has_element?(view, "#edit_version_omop_integration input[value='partial']")

    for {value, icon} <- [yes: "app-check-circle-out", no: "hero-x-mark"] do
      view
      |> form("#edit-form", edit_version: %{omop_integration: Atom.to_string(value)})
      |> render_change()

      assert Repo.get!(DatasetVersion, ctx.current.id).omop_integration == value
      {:ok, index, _html} = live(conn, ~p"/")
      assert has_element?(index, "#{cell} .omop-mapped.is-#{value} svg.#{icon}")
    end

    view
    |> form("#edit-form", edit_version: %{omop_integration: ""})
    |> render_change()

    assert Repo.get!(DatasetVersion, ctx.current.id).omop_integration == nil
    assert_replayable()
  end

  # NOTE(Claude Opus 5.5 2026-11-17): coverage years, emptied by hand (no
  # Clear button any more).
  test "coverage years can be cleared", %{conn: conn} = ctx do
    view = edit_row(conn, ctx.current)

    assert has_element?(
             view,
             "#edit-form input[name='edit_version[coverage_start]'][value='2013']"
           )

    view
    |> form("#edit-form", edit_version: %{coverage_start: ""})
    |> render_change()

    assert has_element?(view, "#edit-status", "Saved.")
    version = Repo.get!(DatasetVersion, ctx.current.id)
    assert version.coverage_start == nil
    assert_replayable()
  end

  # NOTE(Claude Opus 5.5 2026-11-17): a partial year, typed on the way to a
  # full one, is not saved.
  test "coverage years are saved only once whole", %{conn: conn} = ctx do
    view = edit_row(conn, ctx.current)
    set_before = last_change_set()

    view |> form("#edit-form", edit_version: %{coverage_start: "201"}) |> render_change()
    assert has_element?(view, "#edit-form", "must be a year from 1800 to 2100")
    assert last_change_set() == set_before

    view |> form("#edit-form", edit_version: %{coverage_start: "2010"}) |> render_change()
    assert has_element?(view, "#edit-status", "Saved.")
    assert Repo.get!(DatasetVersion, ctx.current.id).coverage_start == 2010
    assert_replayable()
  end

  # NOTE(Claude 2026-11-17): through any version, no longer the current one only.
  test "the dataset name is editable through any version", %{conn: conn} = ctx do
    view = edit_row(conn, ctx.current)
    view |> form("#edit-form", edit_dataset: %{name: "Kanta labs"}) |> render_change()
    assert Repo.get!(Dataset, ctx.dataset.id).name == "Kanta labs"

    view = edit_row(conn, ctx.old)
    view |> form("#edit-form", edit_dataset: %{name: "Kanta lab results"}) |> render_change()
    assert has_element?(view, "#edit-status", "Saved.")
    assert Repo.get!(Dataset, ctx.dataset.id).name == "Kanta lab results"
    assert_replayable()
  end

  # NOTE(Claude 2026-11-09): like the name, a field of the dataset itself.
  test "the description is editable through any version, and shown", %{conn: conn} = ctx do
    assert has_element?(edit_row(conn, ctx.old), "input[name='edit_dataset[description]']")

    view = edit_row(conn, ctx.current)
    assert has_element?(view, "#edit-form input[name='edit_dataset[description]']")
    view |> form("#edit-form", edit_dataset: %{description: "Lab results"}) |> render_change()

    assert has_element?(view, "#edit-status", "Saved.")
    assert Repo.get!(Dataset, ctx.dataset.id).description == "Lab results"

    {:ok, index, _html} = live(conn, ~p"/")

    assert has_element?(
             index,
             "#version-#{ctx.current.id} th .dataset-description",
             "Lab results"
           )

    refute has_element?(index, "#version-#{ctx.old.id} th .dataset-description", "Lab results")

    view |> form("#edit-form", edit_dataset: %{description: ""}) |> render_change()
    assert Repo.get!(Dataset, ctx.dataset.id).description == nil
    assert_replayable()
  end

  test "a too long description is shown as an error and not saved", %{conn: conn} = ctx do
    view = edit_row(conn, ctx.current)
    too_long = String.duplicate("x", Dataset.description_max_length() + 1)
    view |> form("#edit-form", edit_dataset: %{description: too_long}) |> render_change()

    assert has_element?(view, "#edit-status", "Not saved")
    assert has_element?(view, "#edit_dataset_description-errors", "at most 120")
    assert Repo.get!(Dataset, ctx.dataset.id).description == nil
  end

  # NOTE(Claude 2026-11-12): a tick marks each field changed here and saved.
  describe "saved ticks" do
    defp change_field(view, params, target) do
      view |> form("#edit-form", params) |> render_change(%{"_target" => target})
    end

    test "no field has a tick before a change", %{conn: conn} = ctx do
      view = edit_row(conn, ctx.current)
      refute has_element?(view, "#edit-form .saved-tick")
    end

    test "location entries are autosaved after validation", %{conn: conn} = ctx do
      view = edit_row(conn, ctx.current)

      view
      |> form("#edit-form")
      |> render_change(%{
        "edit_version" => %{"locations_sort" => ["new"]},
        "_target" => ["edit_version", "locations_sort"]
      })

      assert has_element?(view, "#edit_version_locations_0_value")
      target = ["edit_version", "locations", "0", "value"]

      change_field(view, %{edit_version: %{locations: %{"0" => %{value: "shared-data"}}}}, target)
      assert has_element?(view, "#edit_version_locations_0_value[aria-invalid]")
      assert Repo.get!(DatasetVersion, ctx.current.id).locations == []

      change_field(
        view,
        %{edit_version: %{locations: %{"0" => %{value: "gs://finngen/kanta", label: "Cloud"}}}},
        target
      )

      assert has_element?(view, "#edit_version_locations-saved")

      assert [%{value: "gs://finngen/kanta", label: "Cloud"}] =
               Repo.get!(DatasetVersion, ctx.current.id).locations

      view
      |> form("#edit-form")
      |> render_change(%{
        "edit_version" => %{"locations_sort" => ["0"], "locations_drop" => ["0"]},
        "_target" => ["edit_version", "locations_drop"]
      })

      refute has_element?(view, "#edit_version_locations_0_value")
      assert Repo.get!(DatasetVersion, ctx.current.id).locations == []
      assert_replayable()
    end

    test "the status and Done are in the form's footer", %{conn: conn} = ctx do
      view = edit_row(conn, ctx.current)
      assert has_element?(view, "#edit-form > #edit-form-footer #edit-status")
      assert has_element?(view, "#edit-form-footer #done-editing")
    end

    test "a saved change ticks its field only", %{conn: conn} = ctx do
      view = edit_row(conn, ctx.current)
      change_field(view, %{edit_version: %{lead: "Joe Bloggs"}}, ["edit_version", "lead"])

      assert has_element?(view, "#edit_version_lead-saved")
      refute has_element?(view, "#edit_version_cohort_size-saved")

      change_field(view, %{edit_version: %{coverage_start: "2001"}}, [
        "edit_version",
        "coverage_start"
      ])

      assert has_element?(view, "#edit_version_lead-saved")
      assert has_element?(view, "#edit_version_coverage_start-saved")
    end

    test "the CSV text, a documentation entry and the dataset name are ticked",
         %{conn: conn} = ctx do
      view = edit_row(conn, ctx.current)

      change_field(view, %{edit_version: %{yearly_counts_csv: "2013,1200"}}, [
        "edit_version",
        "yearly_counts_csv"
      ])

      change_field(view, %{edit_dataset: %{name: "Kanta labs"}}, ["edit_dataset", "name"])

      assert has_element?(view, "#edit_version_yearly_counts_csv-saved")
      assert has_element?(view, "#edit_dataset_name-saved")
    end

    test "an invalid change removes the tick, its fix saves the waiting fields",
         %{conn: conn} = ctx do
      view = edit_row(conn, ctx.current)
      change_field(view, %{edit_version: %{cohort_size: "10"}}, ["edit_version", "cohort_size"])
      assert has_element?(view, "#edit_version_cohort_size-saved")

      change_field(view, %{edit_version: %{cohort_size: "-1"}}, ["edit_version", "cohort_size"])
      refute has_element?(view, "#edit_version_cohort_size-saved")

      # NOTE(Claude 2026-11-12): not saved while the cohort size is invalid,
      # so not ticked; saved, and ticked, once it is fixed.
      change_field(view, %{edit_version: %{lead: "Joe Bloggs"}}, ["edit_version", "lead"])
      refute has_element?(view, "#edit_version_lead-saved")

      change_field(view, %{edit_version: %{cohort_size: "12"}}, ["edit_version", "cohort_size"])
      assert has_element?(view, "#edit_version_cohort_size-saved")
      assert has_element?(view, "#edit_version_lead-saved")
    end
  end

  test "invalid changes are shown and not saved", %{conn: conn} = ctx do
    other = dataset_fixture(%{name: "Taken"})
    version_fixture(other)
    view = edit_row(conn, ctx.current)
    set_before = last_change_set()

    view |> form("#edit-form", edit_version: %{cohort_size: "-1"}) |> render_change()
    assert has_element?(view, "#edit-status", "Not saved")
    assert has_element?(view, "#edit-form", "must be greater than 0")

    # NOTE(Claude 2026-11-03): only the database knows the name is taken.
    view
    |> form("#edit-form", edit_dataset: %{name: "Taken"}, edit_version: %{cohort_size: "1"})
    |> render_change()

    assert has_element?(view, "#edit-form", "has already been taken")
    assert last_change_set() == set_before
    assert Repo.get!(DatasetVersion, ctx.current.id).cohort_size == ctx.current.cohort_size
  end

  test "the data dictionary and yearly counts are edited as CSV text", %{conn: conn} = ctx do
    view = edit_row(conn, ctx.current)
    textarea = "#edit-form textarea[name='edit_version[yearly_counts_csv]']"

    # NOTE(Claude 2026-11-03): prefilled with the saved entries (see the fixture).
    assert view
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query(textarea)
           |> LazyHTML.text() ==
             "2013,10\n2025,100"

    assert has_element?(
             view,
             "#edit-form textarea[name='edit_version[data_dictionary_csv]']",
             "FINNGENID,Participant identifier"
           )

    years = Enum.map_join(1953..2022, "\n", &"#{&1},#{&1}")
    view |> form("#edit-form", edit_version: %{yearly_counts_csv: years}) |> render_change()

    assert has_element?(view, "#edit-status", "Saved.")
    assert length(Repo.get!(DatasetVersion, ctx.current.id).yearly_counts) == 70
    assert_replayable()
  end

  test "a malformed CSV line is shown and nothing is saved", %{conn: conn} = ctx do
    view = edit_row(conn, ctx.current)
    set_before = last_change_set()

    view
    |> form("#edit-form", edit_version: %{yearly_counts_csv: "2013,10\n2014,lots"})
    |> render_change()

    assert has_element?(view, "#edit-status", "Not saved")
    assert has_element?(view, "#edit-form", "line 2: count is invalid")
    # The text stays as typed.
    assert has_element?(view, "#edit-form textarea", "2014,lots")
    assert last_change_set() == set_before
  end

  test "a version name already used by the dataset is shown as an error", %{conn: conn} = ctx do
    view = edit_row(conn, ctx.current)
    set_before = last_change_set()

    view |> form("#edit-form", edit_version: %{version: ctx.old.version}) |> render_change()

    assert has_element?(view, "#edit-form", "has already been taken")
    assert last_change_set() == set_before
  end

  # NOTE(Claude Opus 5.5 2026-11-17): the other viewer is a visitor, who does
  # not see the maintainer: a tag is changed instead.
  test "other viewers see the change live", %{conn: conn} = ctx do
    {:ok, other, _html} = live(Plug.Test.init_test_session(build_conn(), %{}), ~p"/")
    view = edit_row(conn, ctx.current)

    view |> form("#edit-form", edit_version: %{tags: "Livetag"}) |> render_change()

    assert has_element?(other, "#version-#{ctx.current.id}", "Livetag")
  end

  test "the edit page never creates the new dataset draft", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/datasets/new")
    render_change(view, "validate", %{"dataset" => %{"name" => "Half done"}})

    view = edit_row(conn, ctx.current)

    # NOTE(Claude 2026-11-04): Enter in the edit form submits it, which only saves
    # the edit; neither it nor stray new-dataset events may touch the draft.
    view |> form("#edit-form", edit_version: %{lead: "x"}) |> render_submit()
    assert has_element?(view, "#edit-status", "Saved.")
    render_submit(view, "save", %{"dataset" => %{"name" => "Sneaky"}})
    render_change(view, "validate", %{"dataset" => %{"name" => "Sneaky"}})
    render_click(view, "discard", %{})
    assert Repo.aggregate(Dataset, :count) == 1

    {:ok, index, _html} = live(conn, ~p"/")

    {:ok, new, _html} =
      index
      |> element("#add-dataset", "Continue adding dataset")
      |> render_click()
      |> follow_redirect(conn, ~p"/datasets/new")

    assert has_element?(new, "#dataset-form input[name='dataset[name]'][value='Half done']")
  end

  # NOTE(Claude 2026-11-06): someone else's changes to the row being edited.
  describe "someone else's changes" do
    # NOTE(Claude 2026-11-06): as a browser sends it, with the changed field
    # as `_target` (`render_change/2` does not add it).
    defp type_lead(view, lead) do
      view
      |> form("#edit-form", edit_version: %{lead: lead})
      |> render_change(%{"_target" => ["edit_version", "lead"]})
    end

    defp change_elsewhere(ctx, version_attrs, dataset_attrs \\ %{}) do
      version = Repo.get!(DatasetVersion, ctx.current.id)
      dataset = Repo.get!(Dataset, ctx.dataset.id)

      {:ok, _} =
        FGDataCatalog.Catalog.update_dataset_row(dataset, dataset_attrs, version, version_attrs,
          scope: scope_fixture(:other_editor)
        )
    end

    test "this form's own saves show no notice", %{conn: conn} = ctx do
      view = edit_row(conn, ctx.current)
      type_lead(view, "Mine")
      _ = render(view)
      refute has_element?(view, "#edit-notice")
    end

    test "fields not changed here take their new values", %{conn: conn} = ctx do
      view = edit_row(conn, ctx.current)
      type_lead(view, "Mine")

      change_elsewhere(ctx, %{cohort_size: 1234}, %{name: "Renamed"})
      _ = render(view)

      assert has_element?(view, "#edit-notice-updated", "Dataset")
      assert has_element?(view, "#edit-notice-updated", "Individuals covered")
      refute has_element?(view, "#edit-notice-conflicts")

      assert has_element?(
               view,
               "#edit-form input[name='edit_version[cohort_size]'][value='1234']"
             )

      assert has_element?(view, "#edit-form input[name='edit_dataset[name]'][value='Renamed']")
      assert has_element?(view, "#edit-form input[name='edit_version[lead]'][value='Mine']")
    end

    test "fields changed here keep this form's values, and the next change saves them",
         %{conn: conn} = ctx do
      view = edit_row(conn, ctx.current)
      type_lead(view, "Mine")

      change_elsewhere(ctx, %{lead: "Theirs"})
      _ = render(view)

      assert has_element?(view, "#edit-notice-conflicts", "Maintainer")
      assert has_element?(view, "#edit-form input[name='edit_version[lead]'][value='Mine']")
      assert Repo.get!(DatasetVersion, ctx.current.id).lead == "Theirs"

      view |> form("#edit-form", edit_version: %{cohort_size: "42"}) |> render_change()
      assert %{lead: "Mine", cohort_size: 42} = Repo.get!(DatasetVersion, ctx.current.id)
      assert_replayable()
    end

    # NOTE(Claude 2026-11-09): the description is tracked like the name.
    test "a description changed elsewhere is taken, or kept if typed here", %{conn: conn} = ctx do
      view = edit_row(conn, ctx.current)
      change_elsewhere(ctx, %{}, %{description: "Theirs"})
      _ = render(view)

      assert has_element?(view, "#edit-notice-updated", "Description")

      assert has_element?(
               view,
               "#edit-form input[name='edit_dataset[description]'][value='Theirs']"
             )

      view
      |> form("#edit-form", edit_dataset: %{description: "Mine"})
      |> render_change(%{"_target" => ["edit_dataset", "description"]})

      change_elsewhere(ctx, %{}, %{description: "Theirs again"})
      _ = render(view)

      assert has_element?(view, "#edit-notice-conflicts", "Description")

      assert has_element?(
               view,
               "#edit-form input[name='edit_dataset[description]'][value='Mine']"
             )
    end

    # NOTE(Claude 2026-11-12): the tick of a field changed here is removed when
    # someone else changes it, as it then holds their value.
    test "a field changed elsewhere loses its saved tick", %{conn: conn} = ctx do
      view = edit_row(conn, ctx.current)
      type_lead(view, "Mine")
      assert has_element?(view, "#edit_version_lead-saved")

      change_elsewhere(ctx, %{lead: "Theirs"})
      _ = render(view)

      refute has_element?(view, "#edit_version_lead-saved")
    end

    test "a version that no longer exists sends back to the catalog", %{conn: conn} = ctx do
      version = version_fixture(ctx.dataset, %{version: "R99", release_date: ~D[2027-01-01]})
      set_id = Repo.one(from s in ChangeSet, select: max(s.id))
      view = edit_row(conn, version)

      {:ok, _} = FGDataCatalog.Catalog.revert_change_set(scope_fixture(:other_editor), set_id)
      assert_redirect(view, ~p"/")
    end
  end

  # NOTE(Claude 2026-11-16): a Draft's edits of the dataset's name and
  # description stay off the Published rows until the Draft is published.
  describe "the dataset's name through a Draft" do
    setup ctx do
      draft =
        version_fixture(ctx.dataset, %{version: "R15", release_date: ~D[2026-09-01]},
          state: :draft,
          owning_editor_id: user_id(:editor)
        )

      %{draft: draft}
    end

    defp rename_through(view, name) do
      view
      |> form("#edit-form", edit_dataset: %{name: name})
      |> render_change(%{"_target" => ["edit_dataset", "name"]})
    end

    test "is not visible to a visitor nor on the Published row, until publish",
         %{conn: conn} = ctx do
      view = edit_row(conn, ctx.draft)
      rename_through(view, "Kanta renamed")
      assert has_element?(view, "#edit-status", "Saved.")
      assert has_element?(view, "#form-title", "Edit Kanta renamed R15")

      assert Repo.get!(Dataset, ctx.dataset.id).name == "Kanta lab values"

      # The editor sees the Draft, the top row, with its proposed name.
      {:ok, index, _html} = live(conn, ~p"/")
      assert has_element?(index, "#version-#{ctx.draft.id}.current-version th", "Kanta renamed")

      # The Published row, and the visitor, keep the dataset's own name.
      {:ok, visitor, _html} = live(build_conn(), ~p"/")

      assert has_element?(
               visitor,
               "#version-#{ctx.current.id}.current-version th",
               "Kanta lab values"
             )

      refute has_element?(visitor, "#dataset-#{ctx.dataset.id}", "Kanta renamed")

      {:ok, published_edit, _html} = live(conn, ~p"/versions/#{ctx.current.id}/edit")
      assert has_element?(published_edit, "#form-title", "Edit Kanta lab values R14")

      # Publish from the edit page: the name is applied to the dataset.
      {:ok, index, _html} =
        view
        |> element("#edit-publish")
        |> render_click()
        |> follow_redirect(conn, ~p"/")

      assert has_element?(index, "#flash-info", "Published Kanta renamed R15")
      assert Repo.get!(Dataset, ctx.dataset.id).name == "Kanta renamed"

      {:ok, visitor, _html} = live(build_conn(), ~p"/")
      assert has_element?(visitor, "#version-#{ctx.draft.id}.current-version th", "Kanta renamed")
      assert_replayable()
    end

    test "publish is refused if another dataset took the name meanwhile", %{conn: conn} = ctx do
      view = edit_row(conn, ctx.draft)
      rename_through(view, "Wanted")
      dataset_fixture(%{name: "Wanted"})

      {:ok, index, _html} = live(conn, ~p"/")
      index |> element("#publish-version-#{ctx.draft.id}") |> render_click()

      assert has_element?(index, "#flash-error", "has already been taken")
      assert Repo.get!(DatasetVersion, ctx.draft.id).state == :draft
      assert Repo.get!(Dataset, ctx.dataset.id).name == "Kanta lab values"
    end
  end

  # NOTE(Claude 2026-11-17): a newer Draft by another editor is the top row,
  # yet the dataset stays renamable by any editor through its Published version.
  @tag role: :other_editor
  test "under someone else's newer Draft, the Published row renames the dataset",
       %{conn: conn} = ctx do
    draft =
      version_fixture(ctx.dataset, %{version: "R15", release_date: ~D[2026-09-01]},
        state: :draft,
        owning_editor_id: user_id(:editor)
      )

    view = edit_row(conn, ctx.current)

    view
    |> form("#edit-form", edit_dataset: %{name: "Kanta labs"})
    |> render_change(%{"_target" => ["edit_dataset", "name"]})

    assert Repo.get!(Dataset, ctx.dataset.id).name == "Kanta labs"
    assert Repo.get!(DatasetVersion, draft.id).dataset_name == nil

    {:ok, index, _html} = live(conn, ~p"/")
    assert has_element?(index, "#version-#{draft.id}.current-version th", "Kanta labs")
    assert_replayable()
  end

  describe "write rights" do
    test "the edit page offers Publish for the owning editor's Draft only", %{conn: conn} = ctx do
      draft =
        version_fixture(ctx.dataset, %{version: "R15", release_date: ~D[2026-09-01]},
          state: :draft,
          owning_editor_id: user_id(:editor)
        )

      assert has_element?(edit_row(conn, draft), "#edit-publish")
      refute has_element?(edit_row(conn, ctx.current), "#edit-publish")
    end

    test "the edit page is left when the version is taken over meanwhile",
         %{conn: conn} = ctx do
      draft =
        version_fixture(ctx.dataset, %{version: "R15", release_date: ~D[2026-09-01]},
          state: :draft,
          owning_editor_id: user_id(:editor)
        )

      view = edit_row(conn, draft)
      other = scope_fixture(:other_editor)
      {:ok, _} = FGDataCatalog.Catalog.archive_version(other, draft)
      {:ok, _} = FGDataCatalog.Catalog.unarchive_version(other, draft)

      assert_redirect(view, ~p"/")
    end

    # NOTE(Claude 2026-11-16): the save itself is refused, whatever the page
    # holds: the server check reads the version from the database.
    test "a save on a version taken over meanwhile is refused", %{conn: conn} = ctx do
      draft =
        version_fixture(ctx.dataset, %{version: "R15", release_date: ~D[2026-09-01]},
          state: :draft,
          owning_editor_id: user_id(:editor)
        )

      view = edit_row(conn, draft)
      # Taken over without telling the page (no broadcast).
      Repo.update_all(from(v in DatasetVersion, where: v.id == ^draft.id),
        set: [owning_editor_id: user_id(:other_editor)]
      )

      view
      |> form("#edit-form", edit_version: %{lead: "Mine"})
      |> render_change(%{"_target" => ["edit_version", "lead"]})

      assert_redirect(view, ~p"/")
      assert Repo.get!(DatasetVersion, draft.id).lead == "Jane Doe"
    end
  end
end
