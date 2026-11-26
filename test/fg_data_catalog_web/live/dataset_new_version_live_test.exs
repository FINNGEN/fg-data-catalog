defmodule FGDataCatalogWeb.DatasetNewVersionLiveTest do
  # NOTE(Claude 2026-11-06): tests of adding a version to an existing dataset
  # (`/datasets/:id/versions/new`).
  use FGDataCatalogWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import FGDataCatalog.CatalogFixtures
  import FGDataCatalog.DataCase, only: [assert_replayable: 0]

  alias FGDataCatalog.Catalog
  alias FGDataCatalog.Catalog.DatasetVersion
  alias FGDataCatalog.Repo

  setup do
    dataset = dataset_fixture(%{name: "Kanta lab values"})

    current =
      version_fixture(dataset, %{
        version: "R14",
        release_date: ~D[2026-03-13],
        tags: ["Phenotype"],
        lead: "Jane Doe",
        omop_integration: :no,
        doc_links: [%{label: "README", url: "https://example.org/README"}]
      })

    %{
      dataset: dataset,
      current: current
    }
  end

  # NOTE(Claude Opus 5.5 2026-11-17): the individuals covered are no longer
  # prefilled (see `Catalog.new_version_params/1`), so each submit gives them
  # (optional, but checked after submit).
  defp submit(view, params) do
    params = Map.put_new(params, "cohort_size", "1000")
    view |> form("#version-form") |> render_submit(%{"version" => params})
  end

  test "Add version opens a form prefilled from the latest version", %{conn: conn} = ctx do
    {:ok, index, _html} = live(conn, ~p"/")

    {:ok, view, _html} =
      index
      |> element("#add-version-#{ctx.dataset.id}")
      |> render_click()
      |> follow_redirect(conn, ~p"/datasets/#{ctx.dataset.id}/versions/new")

    assert has_element?(view, "#form-title", "Add a version of Kanta lab values")

    # NOTE(Claude-Opus-5.5 2026-11-26): from 2016 to the end of next year.
    {min, max} = FGDataCatalog.Catalog.DatasetVersion.release_date_bounds()
    assert has_element?(view, "input[type=date][min='#{min}'][max='#{max}']")
    assert has_element?(view, "#prefilled-from", "R14")
    assert has_element?(view, "#version-form input[name='version[version]'][autofocus]")
    assert has_element?(view, "#version-form input[name='version[version]']:not([value])")
    assert has_element?(view, "#version-form input[name='version[lead]'][value='Jane Doe']")
    assert has_element?(view, "#version-form input[name='version[tags]'][value='Phenotype']")
    # NOTE(Claude 2026-11-10): the coverage period and individuals covered
    # change with each release, so they start empty.
    assert has_element?(view, "#version-form input[name='version[cohort_size]']:not([value])")
    assert has_element?(view, "#version-form input[name='version[coverage_start]']:not([value])")
    assert has_element?(view, "#version-form input[name='version[coverage_end]']:not([value])")

    assert has_element?(
             view,
             "#version-form input[type='radio'][name='version[omop_integration]'][value='no'][checked]"
           )

    assert has_element?(
             view,
             "#version-form input[name='version[doc_links][0][url]'][value='https://example.org/README']"
           )
  end

  test "Submit adds the version, which becomes the current one", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/datasets/#{ctx.dataset.id}/versions/new")

    {:ok, index, _html} =
      view
      |> submit(%{"version" => "R15", "release_date" => "2026-09-01"})
      |> follow_redirect(conn, ~p"/")

    version = Repo.get_by!(DatasetVersion, dataset_id: ctx.dataset.id, version: "R15")
    assert version.lead == "Jane Doe"
    assert version.tags == ["Phenotype"]
    assert version.omop_integration == :no
    assert [%{label: "README"}] = version.doc_links
    assert version.data_dictionary == []
    assert version.cohort_size == 1000
    assert version.coverage_start == nil
    # NOTE(Claude 2026-11-16): a Draft owned by its creator, the dataset's top row.
    assert version.state == :draft
    assert version.owning_editor_id == user_id(:editor)

    assert has_element?(index, "#version-#{version.id}.current-version")
    assert has_element?(index, "#version-#{ctx.current.id}.previous-version")
    assert_replayable()
  end

  test "errors are shown and nothing is saved", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/datasets/#{ctx.dataset.id}/versions/new")

    submit(view, %{"version" => "R14", "release_date" => "2026-09-01"})

    assert has_element?(view, "#version-form", "has already been taken")
    assert Repo.aggregate(DatasetVersion, :count) == 1
  end

  test "an unknown dataset sends back to the catalog", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => _}}}} =
             live(conn, ~p"/datasets/999999/versions/new")
  end

  @tag role: :visitor
  test "a visitor cannot add a version", %{conn: conn} = ctx do
    assert {:error, {:live_redirect, %{to: "/"}}} =
             live(conn, ~p"/datasets/#{ctx.dataset.id}/versions/new")
  end

  # NOTE(Claude 2026-11-16): every editor, no longer admins only.
  test "an editor may add to a dataset whose versions are all archived", %{conn: conn} = ctx do
    {:ok, _} = Catalog.archive_version(scope_fixture(:other_editor), ctx.current)

    {:ok, view, _html} = live(conn, ~p"/datasets/#{ctx.dataset.id}/versions/new")
    assert has_element?(view, "#prefilled-from", "R14")
    submit(view, %{"version" => "R15", "release_date" => "2026-09-01"})

    assert Catalog.list_published_datasets() == []

    assert [%{versions: [%{version: "R15", state: :draft}]}] =
             Catalog.list_datasets(scope_fixture(:editor))
  end
end
