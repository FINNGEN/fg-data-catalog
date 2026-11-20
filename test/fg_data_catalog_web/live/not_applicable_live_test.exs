defmodule FGDataCatalogWeb.NotApplicableLiveTest do
  # NOTE(Claude Opus 5.5 2026-11-19): the Not applicable values (see
  # `DatasetVersion.not_applicable_fields/0`, `DataQuality` and OMOP-mapped):
  # shown as "n/a" in the catalog, set on the edit page and in the quick edit,
  # told in words on the changelog page. Not async: the edit page and the
  # catalog receive other tests' broadcasts.
  use FGDataCatalogWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import FGDataCatalog.CatalogFixtures
  import FGDataCatalog.DataCase, only: [assert_replayable: 0]

  alias FGDataCatalog.Catalog.{DataQuality, DatasetVersion}
  alias FGDataCatalog.Repo

  setup do
    dataset = dataset_fixture(%{name: "Clinical endpoints"})

    # NOTE(Claude Opus 5.5 2026-11-19): a version with nothing applicable, and
    # one with values (the fixture's). Created through the changelog (the
    # fixture's years and cohort size are dropped), so that it replays.
    na =
      version_fixture(dataset, %{
        version: "v1",
        release_date: ~D[2025-01-01],
        not_applicable: ["years_coverage", "cohort_size"],
        omop_integration: :not_applicable,
        data_quality: Map.new(DataQuality.criteria(), &{&1.key, "na"})
      })

    current = version_fixture(dataset, %{version: "v2", release_date: ~D[2026-01-01]})

    %{dataset: dataset, na: na, current: current}
  end

  describe "the catalog" do
    @describetag role: :visitor

    test "shows n/a, not the dash, in the cells that do not apply", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/")
      row = "#version-#{ctx.na.id}"

      # OMOP-mapped, years coverage and cohort coverage.
      assert view
             |> element(row)
             |> render()
             |> LazyHTML.from_fragment()
             |> count(".not-applicable") ==
               3

      assert has_element?(view, "#{row} .not-applicable[title='Not applicable']")
      refute has_element?(view, "#{row} .omop .no-value")

      # Data quality: n/a, not a score.
      assert has_element?(view, "#quality-link-#{ctx.na.id}[data-level='na']", "n/a")

      assert has_element?(
               view,
               "#quality-link-#{ctx.na.id}[aria-label='Data quality of Clinical endpoints v1: not applicable']"
             )

      # The other version has values: no n/a.
      refute has_element?(view, "#version-#{ctx.current.id} .not-applicable")
    end

    test "an unknown value is a dash titled Unknown", %{conn: conn} = ctx do
      ctx.current
      |> DatasetVersion.changeset(%{"cohort_size" => "", "omop_integration" => ""})
      |> Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#version-#{ctx.current.id} .omop .no-value[title='Unknown']")

      assert has_element?(
               view,
               "#version-#{ctx.current.id} .cohort-coverage .no-value[title='Unknown']"
             )
    end

    test "the data quality modal shows the answers, without the If no text",
         %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/?quality=#{ctx.na.id}")

      assert has_element?(view, "#quality-title", "n/a")
      assert has_element?(view, "#quality-answer-documented[data-answer='na']", "Not applicable")
      refute has_element?(view, "#quality-if-no-documented")
    end
  end

  describe "the edit page" do
    test "a data quality criterion may be Not applicable", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/versions/#{ctx.current.id}/edit")

      assert has_element?(view, "#edit_version_data_quality_documented_na")

      view
      |> form("#edit-form", edit_version: %{data_quality: %{"documented" => "na"}})
      |> render_change(%{"_target" => ["edit_version", "data_quality", "documented"]})

      assert has_element?(view, "#edit_version_data_quality_documented_na[checked]")
      total = length(DataQuality.criteria())
      assert has_element?(view, "#edit_version_data_quality-score", "?/#{total - 1}")

      assert Repo.get!(DatasetVersion, ctx.current.id).data_quality["documented"] == "na"
      assert_replayable()
    end

    test "the cohort's checkbox clears its value and disables its input", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/versions/#{ctx.current.id}/edit")

      refute has_element?(view, "#edit_version_cohort_size_not_applicable[checked]")
      refute has_element?(view, "#edit_version_cohort_size[disabled]")

      view
      |> form("#edit-form", edit_version: %{cohort_size_not_applicable: "true"})
      |> render_change(%{"_target" => ["edit_version", "cohort_size_not_applicable"]})

      assert has_element?(view, "#edit-status", "Saved.")
      assert has_element?(view, "#edit_version_cohort_size_not_applicable[checked]")
      assert has_element?(view, "#edit_version_cohort_size[disabled]")
      refute has_element?(view, "#edit_version_cohort_size[value]")

      assert %{not_applicable: ["cohort_size"], cohort_size: nil, coverage_start: 2013} =
               Repo.get!(DatasetVersion, ctx.current.id)

      assert_replayable()
    end

    test "the years' checkbox clears the period and the counts", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/versions/#{ctx.current.id}/edit")

      view
      |> form("#edit-form", edit_version: %{years_not_applicable: "true"})
      |> render_change(%{"_target" => ["edit_version", "years_not_applicable"]})

      assert has_element?(view, "#edit_version_coverage_start[disabled]")
      assert has_element?(view, "#edit_version_coverage_end[disabled]")
      assert has_element?(view, "#edit_version_yearly_counts_csv[disabled]")

      assert %{
               not_applicable: ["years_coverage"],
               coverage_start: nil,
               coverage_end: nil,
               yearly_counts: []
             } = Repo.get!(DatasetVersion, ctx.current.id)

      # Unchecked: applicable again, the inputs empty and enabled.
      view
      |> form("#edit-form", edit_version: %{years_not_applicable: "false"})
      |> render_change(%{"_target" => ["edit_version", "years_not_applicable"]})

      refute has_element?(view, "#edit_version_coverage_start[disabled]")
      assert Repo.get!(DatasetVersion, ctx.current.id).not_applicable == []
      assert_replayable()
    end

    test "the changelog tells the change in words", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/versions/#{ctx.current.id}/edit")

      view
      |> form("#edit-form", edit_version: %{cohort_size_not_applicable: "true"})
      |> render_change(%{"_target" => ["edit_version", "cohort_size_not_applicable"]})

      {:ok, changelog, _html} = live(conn, ~p"/changelog")
      assert has_element?(changelog, "#changes .change-diff dt", "not_applicable")
      assert has_element?(changelog, "#changes .quality-diff", "Cohort coverage")
      assert has_element?(changelog, "#changes .quality-diff del", "Applicable")
      assert has_element?(changelog, "#changes .quality-diff ins", "Not applicable")
    end
  end

  describe "the quick edit" do
    defp open_editor_mode(conn) do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#editor-mode-toggle") |> render_click()
      view
    end

    defp quick_edit(view, version, field) do
      render_hook(view, "quick_edit", %{"id" => to_string(version.id), "field" => field})
    end

    test "the cohort opens in a modal with its checkbox", %{conn: conn} = ctx do
      view = open_editor_mode(conn)

      quick_edit(view, ctx.current, "cohort_size")
      assert has_element?(view, "#quick-edit-modal #quick-edit-title", "Cohort coverage")
      assert has_element?(view, "#quick_version_cohort_size_not_applicable")
      # Only the cohort's: the years' Not applicable is left as it is.
      refute has_element?(view, "#quick_version_years_not_applicable")

      view
      |> form("#quick-edit-form", quick_version: %{cohort_size_not_applicable: "true"})
      |> render_submit()

      refute has_element?(view, "#quick-edit-form")
      assert has_element?(view, "#version-#{ctx.current.id} .not-applicable-cell .not-applicable")
      assert Repo.get!(DatasetVersion, ctx.current.id).not_applicable == ["cohort_size"]
      assert_replayable()
    end

    test "the years modal keeps the cohort's Not applicable", %{conn: conn} = ctx do
      view = open_editor_mode(conn)

      quick_edit(view, ctx.na, "years")

      view
      |> form("#quick-edit-form", quick_version: %{years_not_applicable: "false"})
      |> render_submit()

      assert Repo.get!(DatasetVersion, ctx.na.id).not_applicable == ["cohort_size"]
      assert_replayable()
    end
  end

  defp count(html, selector), do: html |> LazyHTML.query(selector) |> Enum.count()
end
