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
  # prefilled (see `Catalog.new_version_params/1`), so each change gives them.
  # NOTE(Claude-Opus-5.5 2026-11-26): no Submit: a change that makes the form
  # valid creates the draft.
  defp change(view, params) do
    params = Map.put_new(params, "cohort_size", "1000")
    view |> form("#edit-form") |> render_change(%{"edit_version" => params})
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
    assert has_element?(view, "#edit-form input[name='edit_version[version]'][autofocus]")
    assert has_element?(view, "#edit-form input[name='edit_version[version]']:not([value])")
    assert has_element?(view, "#edit-form input[name='edit_version[lead]'][value='Jane Doe']")
    assert has_element?(view, "#edit-form input[name='edit_version[tags]'][value='Phenotype']")
    # NOTE(Claude 2026-11-10): the coverage period and individuals covered
    # change with each release, so they start empty.
    assert has_element?(view, "#edit-form input[name='edit_version[cohort_size]']:not([value])")

    assert has_element?(
             view,
             "#edit-form input[name='edit_version[coverage_start]']:not([value])"
           )

    assert has_element?(view, "#edit-form input[name='edit_version[coverage_end]']:not([value])")

    assert has_element?(
             view,
             "#edit-form input[type='radio'][name='edit_version[omop_integration]'][value='no'][checked]"
           )

    assert has_element?(
             view,
             "#edit-form input[name='edit_version[doc_links][0][url]'][value='https://example.org/README']"
           )
  end

  test "opening the page creates nothing", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/datasets/#{ctx.dataset.id}/versions/new")
    change(view, %{"lead" => "John Doe"})

    assert Repo.aggregate(DatasetVersion, :count) == 1
    assert has_element?(view, "#edit-status", "Fill in Version and Release date")
    assert has_element?(view, "fieldset#optional-fields[disabled]")
    assert has_element?(view, "#edit-publish[disabled]")
  end

  test "a valid form creates a Draft, which becomes the current version",
       %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/datasets/#{ctx.dataset.id}/versions/new")
    change(view, %{"version" => "R15", "release_date" => "2026-09-01"})

    version = Repo.get_by!(DatasetVersion, dataset_id: ctx.dataset.id, version: "R15")
    assert_patch(view, ~p"/versions/#{version.id}/edit")
    assert has_element?(view, "#status-#{version.id}", "My draft")
    {:ok, index, _html} = live(conn, ~p"/")

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

    # NOTE(Claude-Opus-5.5 2026-11-26): another editor sees it on top too.
    assert [%{versions: [%{id: id}, %{id: current_id}]}] =
             Catalog.list_datasets(scope_fixture(:other_editor))

    assert {id, current_id} == {version.id, ctx.current.id}
    assert_replayable()
  end

  # NOTE(Claude-Opus-5.5 2026-11-26): the optional fields are disabled until
  # the draft exists, and a browser does not send them: the prefill is kept.
  test "the draft keeps the prefilled values the browser does not send", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/datasets/#{ctx.dataset.id}/versions/new")

    render_change(view, "validate", %{
      "edit_dataset" => %{"name" => "Kanta lab values"},
      "edit_version" => %{"version" => "R15", "release_date" => "2026-09-01"}
    })

    version = Repo.get_by!(DatasetVersion, dataset_id: ctx.dataset.id, version: "R15")
    assert %{lead: "Jane Doe", tags: ["Phenotype"], omop_integration: :no} = version
    assert [%{label: "README"}] = version.doc_links
    refute has_element?(view, "fieldset[disabled]")
  end

  # NOTE(Claude-Opus-5.5 2026-11-26): saved through the new draft, which
  # proposes them, as the dataset has a Published version.
  test "a changed dataset name is proposed by the new draft", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/datasets/#{ctx.dataset.id}/versions/new")

    view
    |> form("#edit-form")
    |> render_change(%{
      "edit_dataset" => %{"name" => "Kanta lab results"},
      "edit_version" => %{"version" => "R15", "release_date" => "2026-09-01"}
    })

    version = Repo.get_by!(DatasetVersion, dataset_id: ctx.dataset.id, version: "R15")
    assert version.dataset_name == "Kanta lab results"
    assert Repo.reload!(ctx.dataset).name == "Kanta lab values"
    assert has_element?(view, "#form-title", "Edit Kanta lab results R15")
  end

  test "errors are shown and nothing is saved", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/datasets/#{ctx.dataset.id}/versions/new")

    change(view, %{"version" => "R14", "release_date" => "2026-09-01"})

    assert has_element?(view, "#edit-form", "has already been taken")
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
    change(view, %{"version" => "R15", "release_date" => "2026-09-01"})

    assert Catalog.list_published_datasets() == []

    assert [%{versions: [%{version: "R15", state: :draft}]}] =
             Catalog.list_datasets(scope_fixture(:editor))
  end
end
