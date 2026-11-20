defmodule FGDataCatalogWeb.QuickEditLiveTest do
  # NOTE(Claude 2026-11-10): tests of the catalog's quick edit: a hovered cell
  # and the E key (client side, see `.QuickEdit`) send `quick_edit`, simulated
  # here with `render_hook/3`. Not async: the live-update test would receive
  # other tests' broadcasts.
  use FGDataCatalogWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import FGDataCatalog.CatalogFixtures
  import FGDataCatalog.DataCase, only: [assert_replayable: 0]

  alias FGDataCatalog.Catalog.{Dataset, DatasetVersion, YearCount}
  alias FGDataCatalog.Repo

  setup do
    dataset = dataset_fixture(%{name: "Kanta lab values"})
    old = version_fixture(dataset, %{version: "R13", release_date: ~D[2025-03-01]})

    current =
      version_fixture(dataset, %{version: "R14", release_date: ~D[2026-03-13], lead: "Jane"})

    %{dataset: dataset, old: old, current: current}
  end

  defp quick_edit(view, version, field) do
    render_hook(view, "quick_edit", %{"id" => to_string(version.id), "field" => field})
  end

  # NOTE(Claude 2026-11-10): the catalog opens in Viewer mode; the quick edit
  # needs Editor mode (the M key, client side, or the switch).
  defp open_editor_mode(conn) do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#editor-mode-toggle") |> render_click()
    view
  end

  test "the catalog opens in Viewer mode, without quick edit", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#catalog-table[phx-hook$='.CatalogTable'][data-can-edit='true']")
    assert has_element?(view, "#catalog-table[data-editor-mode='false']")
    assert has_element?(view, "#editor-mode-toggle[aria-pressed='false']")
    refute has_element?(view, "#quick-edit-hint")
    refute has_element?(view, "[data-quick-edit]")

    quick_edit(view, ctx.current, "lead")
    refute has_element?(view, "#quick-edit-form")
  end

  test "the M key (or the switch) toggles Editor mode", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "toggle_editor_mode", %{})
    assert has_element?(view, "#editor-mode-toggle.is-on[aria-pressed='true']")
    assert has_element?(view, "#catalog-scroll.is-editor-mode")
    assert has_element?(view, "#quick-edit-hint")
    assert has_element?(view, "[data-quick-edit]")

    render_hook(view, "toggle_editor_mode", %{})
    refute has_element?(view, "#catalog-scroll.is-editor-mode")
    refute has_element?(view, "[data-quick-edit]")
  end

  test "leaving Editor mode closes an open editor", %{conn: conn} = ctx do
    view = open_editor_mode(conn)

    quick_edit(view, ctx.current, "lead")
    assert has_element?(view, "#quick-edit-form")

    render_hook(view, "leave_editor_mode", %{})
    refute has_element?(view, "#quick-edit-form")
    refute has_element?(view, "#catalog-scroll.is-editor-mode")
  end

  test "an editor's cells are marked as quick editable in Editor mode", %{conn: conn} = ctx do
    view = open_editor_mode(conn)

    assert has_element?(view, "#quick-edit-hint")
    assert has_element?(view, "#version-#{ctx.current.id}[data-version-id='#{ctx.current.id}']")

    for field <- ~w(dataset tags environments access_type version release_date modalities
                    formats omop_integration doc_links data_dictionary years data_quality
                    cohort_size lead) do
      assert has_element?(view, "#version-#{ctx.current.id} [data-quick-edit='#{field}']")
    end

    # NOTE(Claude 2026-11-17): the dataset's name through any version.
    assert has_element?(view, "#version-#{ctx.old.id} [data-quick-edit='dataset']")
  end

  test "the dataset's name is quick edited through a previous version", %{conn: conn} = ctx do
    view = open_editor_mode(conn)

    quick_edit(view, ctx.old, "dataset")
    view |> form("#quick-edit-form", quick_dataset: %{name: "Kanta labs"}) |> render_submit()

    assert Repo.get!(Dataset, ctx.dataset.id).name == "Kanta labs"
    assert_replayable()
  end

  @tag role: :visitor
  test "a visitor can neither see nor use the quick edit", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/")

    refute has_element?(view, "#editor-mode")
    refute has_element?(view, "[data-quick-edit]")

    render_hook(view, "toggle_editor_mode", %{})
    refute has_element?(view, "[data-quick-edit]")

    quick_edit(view, ctx.current, "lead")
    refute has_element?(view, "#quick-edit-form")
  end

  test "an inline field is edited in place and saved on submit", %{conn: conn} = ctx do
    view = open_editor_mode(conn)

    quick_edit(view, ctx.current, "lead")
    assert has_element?(view, "#version-#{ctx.current.id} #quick-edit-form")
    assert has_element?(view, "#quick-edit-form input[name='quick_version[lead]'][value='Jane']")
    refute has_element?(view, "#quick-edit-modal")

    view
    |> form("#quick-edit-form", quick_version: %{lead: "John Roe"})
    |> render_submit()

    refute has_element?(view, "#quick-edit-form")
    assert has_element?(view, "#version-#{ctx.current.id} [data-quick-edit='lead']", "John Roe")
    assert Repo.get!(DatasetVersion, ctx.current.id).lead == "John Roe"
    assert_replayable()
  end

  # NOTE(Claude Opus 5.5 2026-11-17): the access type and the individuals
  # covered are optional: the quick edit clears them.
  test "the access type and the individuals covered can be cleared", %{conn: conn} = ctx do
    view = open_editor_mode(conn)

    quick_edit(view, ctx.current, "access_type")
    view |> form("#quick-edit-form", quick_version: %{access_type: ""}) |> render_change()
    refute has_element?(view, "#quick-edit-form")
    assert Repo.get!(DatasetVersion, ctx.current.id).access_type == nil

    quick_edit(view, ctx.current, "cohort_size")
    view |> form("#quick-edit-form", quick_version: %{cohort_size: ""}) |> render_submit()
    refute has_element?(view, "#quick-edit-form")
    assert Repo.get!(DatasetVersion, ctx.current.id).cohort_size == nil

    assert_replayable()
  end

  test "the locations modal validates, saves and removes multiple entries", %{conn: conn} = ctx do
    view = open_editor_mode(conn)
    quick_edit(view, ctx.current, "locations")
    assert has_element?(view, "#quick-edit-modal[open] #quick_version_locations")

    render_change(view, "quick_validate", %{"quick_version" => %{"locations_sort" => ["new"]}})

    view
    |> form("#quick-edit-form", quick_version: %{locations: %{"0" => %{value: "kanta lab"}}})
    |> render_submit()

    assert has_element?(view, "#quick_version_locations_0_value[aria-invalid]")
    assert Repo.get!(DatasetVersion, ctx.current.id).locations == []

    render_change(view, "quick_validate", %{
      "quick_version" => %{
        "locations_sort" => ["0", "new"],
        "locations" => %{"0" => %{"value" => "/finngen/kanta", "label" => "Sandbox"}}
      }
    })

    view
    |> form("#quick-edit-form",
      quick_version: %{locations: %{"1" => %{value: "gs://finngen/kanta", label: "Cloud"}}}
    )
    |> render_submit()

    refute has_element?(view, "#quick-edit-modal")
    assert has_element?(view, "#locations-#{ctx.current.id}", "2 locations")

    assert [%{label: "Sandbox"}, %{label: "Cloud"}] =
             Repo.get!(DatasetVersion, ctx.current.id).locations

    quick_edit(view, ctx.current, "locations")

    render_submit(view, "quick_save", %{
      "quick_version" => %{
        "locations_sort" => ["0", "1"],
        "locations_drop" => ["0"],
        "locations" => %{
          "0" => %{"value" => "/finngen/kanta", "label" => "Sandbox"},
          "1" => %{"value" => "gs://finngen/kanta", "label" => "Cloud"}
        }
      }
    })

    assert has_element?(view, "#locations-#{ctx.current.id}", "Cloud")

    assert [%{value: "gs://finngen/kanta", label: "Cloud"}] =
             Repo.get!(DatasetVersion, ctx.current.id).locations

    assert_replayable()
  end

  test "the dataset's name and description are edited together", %{conn: conn} = ctx do
    view = open_editor_mode(conn)

    quick_edit(view, ctx.current, "dataset")

    view
    |> form("#quick-edit-form", quick_dataset: %{name: "Kanta labs", description: "Lab tests"})
    |> render_submit()

    assert %{name: "Kanta labs", description: "Lab tests"} = Repo.get!(Dataset, ctx.dataset.id)
    assert_replayable()
  end

  test "an invalid value shows its error and is not saved", %{conn: conn} = ctx do
    view = open_editor_mode(conn)

    quick_edit(view, ctx.current, "cohort_size")

    view
    |> form("#quick-edit-form", quick_version: %{cohort_size: "-1"})
    |> render_submit()

    assert has_element?(view, "#quick-edit-form .field-error")
    assert Repo.get!(DatasetVersion, ctx.current.id).cohort_size == ctx.current.cohort_size
  end

  test "Cancel closes the editor without saving", %{conn: conn} = ctx do
    view = open_editor_mode(conn)

    quick_edit(view, ctx.current, "lead")
    view |> form("#quick-edit-form", quick_version: %{lead: "Typed"}) |> render_change()
    view |> element("#quick-edit-cancel") |> render_click()

    refute has_element?(view, "#quick-edit-form")
    assert Repo.get!(DatasetVersion, ctx.current.id).lead == "Jane"
  end

  test "a list field is edited in place, with suggestions", %{conn: conn} = ctx do
    view = open_editor_mode(conn)

    quick_edit(view, ctx.current, "tags")
    refute has_element?(view, "#quick-edit-modal")
    assert has_element?(view, "#version-#{ctx.current.id} #quick-edit-form")

    assert has_element?(
             view,
             "#quick-edit-form input[name='quick_version[tags]'][phx-hook$='.TokenSuggest'][data-suggestions]"
           )

    view
    |> form("#quick-edit-form", quick_version: %{tags: "Lab, Phenotype"})
    |> render_submit()

    refute has_element?(view, "#quick-edit-form")
    assert Repo.get!(DatasetVersion, ctx.current.id).tags == ["Lab", "Phenotype"]
    assert_replayable()
  end

  test "Environment, Modality and Format are edited in place too", %{conn: conn} = ctx do
    view = open_editor_mode(conn)

    for {field, value} <- [environments: "Sandbox, Local", modalities: "Genes", formats: "CSV"] do
      quick_edit(view, ctx.current, Atom.to_string(field))
      assert has_element?(view, "#version-#{ctx.current.id} #quick-edit-form")

      view
      |> form("#quick-edit-form", quick_version: %{field => value})
      |> render_submit()
    end

    assert %{environments: ["Local", "Sandbox"], modalities: ["Genes"], formats: ["CSV"]} =
             Repo.get!(DatasetVersion, ctx.current.id)
  end

  test "a field with several entries opens in a modal", %{conn: conn} = ctx do
    view = open_editor_mode(conn)

    quick_edit(view, ctx.current, "data_dictionary")
    assert has_element?(view, "#quick-edit-modal #quick-edit-form")
    assert has_element?(view, "#quick-edit-title", "Kanta lab values R14 · Data dictionary")
    refute has_element?(view, "#quick-edit-form input[name='quick_version[lead]']")

    view
    |> form("#quick-edit-form", quick_version: %{data_dictionary_csv: "ID,Identifier"})
    |> render_submit()

    refute has_element?(view, "#quick-edit-modal")
    assert [%{col_name: "ID"}] = Repo.get!(DatasetVersion, ctx.current.id).data_dictionary
    assert_replayable()
  end

  # NOTE(Claude 2026-11-10): Enter does not submit a form from a select.
  test "a select saves on change", %{conn: conn} = ctx do
    view = open_editor_mode(conn)

    quick_edit(view, ctx.current, "access_type")
    view |> form("#quick-edit-form", quick_version: %{access_type: "public"}) |> render_change()

    refute has_element?(view, "#quick-edit-form")
    assert Repo.get!(DatasetVersion, ctx.current.id).access_type == :public
  end

  # NOTE(Claude Opus 5.5 2026-11-19): then Not applicable.
  test "the quick edit of OMOP-mapped cycles Unknown, Yes, No, Not applicable",
       %{conn: conn} = ctx do
    view = open_editor_mode(conn)

    for expected <- [:yes, :no, :not_applicable, nil, :yes] do
      quick_edit(view, ctx.current, "omop_integration")
      refute has_element?(view, "#quick-edit-form")
      assert Repo.get!(DatasetVersion, ctx.current.id).omop_integration == expected
    end

    assert_replayable()
  end

  test "OMOP-mapped does not cycle in Viewer mode", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/")

    quick_edit(view, ctx.current, "omop_integration")

    assert %{omop_integration: nil} = Repo.get!(DatasetVersion, ctx.current.id)
  end

  # NOTE(Claude 2026-11-16): in Editor mode, the score is plain text and its
  # cell opens the quick edit modal: the form's Data quality section, saved on
  # Save as one change set.
  test "the data quality modal edits the answers", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#quality-link-#{ctx.current.id}")

    view |> element("#editor-mode-toggle") |> render_click()
    refute has_element?(view, "#quality-link-#{ctx.current.id}")
    assert has_element?(view, "#quality-score-#{ctx.current.id}", "?/7")

    quick_edit(view, ctx.current, "data_quality")
    assert has_element?(view, "#quick-edit-modal #quick-edit-title", "Data quality")
    assert has_element?(view, "#quick_version_data_quality_documented_unknown[checked]")
    refute has_element?(view, "#quick-edit-form input[name='quick_version[tags]']")

    view
    |> form("#quick-edit-form",
      quick_version: %{data_quality: %{"documented" => "yes", "in_one_piece" => "no"}}
    )
    |> render_change()

    # The score follows the choices, before saving (still some Unknown).
    assert has_element?(view, "#quick_version_data_quality-score", "?/7")
    assert Repo.get!(DatasetVersion, ctx.current.id).data_quality == %{}

    view
    |> form("#quick-edit-form",
      quick_version: %{data_quality: %{"documented" => "yes", "in_one_piece" => "no"}}
    )
    |> render_submit()

    refute has_element?(view, "#quick-edit-modal")

    assert Repo.get!(DatasetVersion, ctx.current.id).data_quality ==
             %{"documented" => "yes", "in_one_piece" => "no"}

    assert has_element?(view, "#quality-score-#{ctx.current.id}", "?/7")
    assert_replayable()
  end

  test "the data quality modal's Cancel saves nothing", %{conn: conn} = ctx do
    view = open_editor_mode(conn)
    quick_edit(view, ctx.current, "data_quality")

    view
    |> form("#quick-edit-form", quick_version: %{data_quality: %{"documented" => "yes"}})
    |> render_change()

    view |> element("#quick-edit-cancel") |> render_click()
    refute has_element?(view, "#quick-edit-modal")
    assert Repo.get!(DatasetVersion, ctx.current.id).data_quality == %{}
  end

  test "the documentation modal adds an entry", %{conn: conn} = ctx do
    view = open_editor_mode(conn)

    quick_edit(view, ctx.current, "doc_links")

    render_change(view, "quick_validate", %{
      "quick_version" => %{
        "doc_links_sort" => ["0", "new"],
        "doc_links" => %{
          "0" => %{"kind" => "link", "label" => "README", "url" => "https://example.org/README"}
        }
      }
    })

    assert has_element?(view, "#quick-edit-form input[name='quick_version[doc_links][1][url]']")

    view
    |> form("#quick-edit-form",
      quick_version: %{doc_links: %{"1" => %{label: "Paper", url: "https://example.org/paper"}}}
    )
    |> render_submit()

    assert [%{label: "README"}, %{label: "Paper"}] =
             Repo.get!(DatasetVersion, ctx.current.id).doc_links

    assert_replayable()
  end

  test "the years coverage modal edits the period and the yearly counts", %{conn: conn} = ctx do
    view = open_editor_mode(conn)

    quick_edit(view, ctx.current, "years")

    view
    |> form("#quick-edit-form",
      quick_version: %{
        coverage_start: "2001",
        yearly_counts_csv: "2001,5\n2002,7"
      }
    )
    |> render_submit()

    version = Repo.get!(DatasetVersion, ctx.current.id)
    assert version.coverage_start == 2001

    assert [%YearCount{year: 2001, count: 5}, %YearCount{year: 2002, count: 7}] =
             version.yearly_counts

    assert_replayable()
  end

  test "the editor stays open when the catalog changes", %{conn: conn} = ctx do
    view = open_editor_mode(conn)

    quick_edit(view, ctx.current, "lead")
    view |> form("#quick-edit-form", quick_version: %{lead: "Typed"}) |> render_change()
    send(view.pid, {:catalog_changed, 0})

    assert has_element?(view, "#quick-edit-form input[name='quick_version[lead]'][value='Typed']")
  end

  # NOTE(Claude 2026-11-16): see `Catalog.can?/3`.
  describe "write rights" do
    test "cannot quick edit someone else's draft", %{conn: conn} = ctx do
      draft =
        version_fixture(ctx.dataset, %{version: "R15", release_date: ~D[2026-09-01]},
          state: :draft,
          owning_editor_id: user_id(:other_editor)
        )

      view = open_editor_mode(conn)

      quick_edit(view, draft, "lead")
      refute has_element?(view, "#quick-edit-form")
    end

    test "quick edits a published version", %{conn: conn} = ctx do
      view = open_editor_mode(conn)

      quick_edit(view, ctx.current, "lead")
      view |> form("#quick-edit-form", quick_version: %{lead: "Ed"}) |> render_submit()

      assert Repo.get!(DatasetVersion, ctx.current.id).lead == "Ed"
    end

    # NOTE(Claude 2026-11-16): checked again on save, against the database.
    test "a quick save on a Draft taken over meanwhile is refused", %{conn: conn} = ctx do
      draft =
        version_fixture(ctx.dataset, %{version: "R15", release_date: ~D[2026-09-01]},
          state: :draft,
          owning_editor_id: user_id(:editor)
        )

      view = open_editor_mode(conn)
      quick_edit(view, draft, "lead")
      assert has_element?(view, "#quick-edit-form")

      # Taken over without telling the page (no broadcast).
      Repo.update_all(from(v in DatasetVersion, where: v.id == ^draft.id),
        set: [owning_editor_id: user_id(:other_editor)]
      )

      view |> form("#quick-edit-form", quick_version: %{lead: "Mine"}) |> render_submit()

      assert has_element?(view, "#flash-error", "no longer edit")
      refute has_element?(view, "#quick-edit-form")
      assert Repo.get!(DatasetVersion, draft.id).lead == "Jane Doe"
    end
  end
end
