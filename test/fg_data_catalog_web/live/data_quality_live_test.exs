defmodule FGDataCatalogWeb.DataQualityLiveTest do
  # NOTE(Claude 2026-11-16): the data quality score: in the catalog (its modal),
  # on the form pages and on the changelog page. Not async: the edit page and
  # the catalog receive other tests' broadcasts.
  use FGDataCatalogWeb.ConnCase, async: false

  import Ecto.Query, only: [where: 2]
  import Phoenix.LiveViewTest
  import FGDataCatalog.CatalogFixtures
  import FGDataCatalog.DataCase, only: [assert_replayable: 0]

  alias FGDataCatalog.Catalog.{DataQuality, DatasetVersion}
  alias FGDataCatalog.Repo

  @total length(DataQuality.criteria())

  setup do
    dataset = dataset_fixture(%{name: "SETD1A"})

    old = version_fixture(dataset, %{version: "v1", release_date: ~D[2025-01-01]})

    current =
      version_fixture(dataset, %{
        version: "v2",
        release_date: ~D[2026-01-01],
        # NOTE(Claude 2026-11-16): every criterion answered (so a count is
        # shown), two of them Yes.
        data_quality:
          DataQuality.criteria()
          |> Map.new(&{&1.key, "no"})
          |> Map.merge(%{"in_one_piece" => "yes", "keyed_by_finngenid" => "yes"})
      })

    %{dataset: dataset, old: old, current: current}
  end

  describe "the catalog" do
    @describetag role: :visitor

    test "shows each version's score, as a link with an accessible name", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#catalog-table thead th", "Data quality")
      assert has_element?(view, "#quality-link-#{ctx.current.id}", "2/#{@total}")
      # A previous version, with nothing answered: unknown.
      assert has_element?(view, "#quality-link-#{ctx.old.id}", "?/#{@total}")
      # Badges by level: 2 of 7 is low; an incomplete score is bare.
      assert has_element?(view, "#quality-link-#{ctx.current.id}.quality-badge[data-level='low']")
      assert has_element?(view, "#quality-link-#{ctx.old.id}.quality-badge[data-level='unknown']")

      assert has_element?(
               view,
               "#quality-link-#{ctx.current.id}[aria-label='Data quality of SETD1A v2: 2 of #{@total} criteria met']"
             )

      assert has_element?(
               view,
               "#quality-link-#{ctx.old.id}[aria-label='Data quality of SETD1A v1: unknown, #{@total} of #{@total} criteria not answered']"
             )
    end

    test "the score opens a modal with every criterion and its answer", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "#quality-modal")

      view |> element("#quality-link-#{ctx.current.id}") |> render_click()
      assert_patch(view, ~p"/?quality=#{ctx.current.id}")

      assert has_element?(view, "#quality-modal #quality-title", "SETD1A v2")
      assert has_element?(view, "#quality-modal #quality-title", "2/#{@total}")

      for criterion <- DataQuality.criteria() do
        assert has_element?(view, "#quality-criterion-#{criterion.key}", criterion.label)
        refute has_element?(view, "#quality-criterion-#{criterion.key}", criterion.question)
      end

      assert has_element?(view, "#quality-answer-in_one_piece[data-answer='yes']", "Yes")
      assert has_element?(view, "#quality-answer-documented[data-answer='no']", "No")
      refute has_element?(view, "#quality-criterion-removed_criterion")
    end

    # NOTE(Claude 2026-11-16): shown at once, for every criterion; no help button.
    test "each criterion shows what to do if not", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/?quality=#{ctx.current.id}")

      assert has_element?(
               view,
               "#quality-criterion-documented #quality-if-no-documented",
               "If no, you have to: reverse-engineer"
             )

      for criterion <- DataQuality.criteria() do
        assert has_element?(view, "#quality-if-no-#{criterion.key}:not([hidden])")
      end

      refute has_element?(view, "#quality-modal button[aria-expanded]")
    end

    test "closing resets the URL, keeping the search", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/?q=SETD1A&quality=#{ctx.current.id}")
      assert has_element?(view, "#quality-modal")

      view |> element("#quality-modal .modal-close") |> render_click()
      assert_patch(view, ~p"/?q=SETD1A")
      refute has_element?(view, "#quality-modal")
    end

    test "a direct link opens it; an unknown id does not", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/?quality=#{ctx.old.id}")
      assert has_element?(view, "#quality-modal #quality-title", "SETD1A v1")
      assert has_element?(view, "#quality-modal #quality-title", "?/#{@total}")
      # Unknown is shown as such, not as No.
      assert has_element?(view, "#quality-answer-documented[data-answer='unknown']", "Unknown")

      {:ok, view, _html} = live(conn, ~p"/?quality=999999")
      refute has_element?(view, "#quality-modal")
    end

    # NOTE(Claude 2026-11-16): written past the changeset, which would drop it,
    # as if the criterion had been removed from the list since.
    test "stored answers to criteria not in the list are neither shown nor counted",
         %{conn: conn} = ctx do
      answers = Map.put(ctx.current.data_quality, "removed_criterion", "yes")

      {1, _} =
        Repo.update_all(where(DatasetVersion, id: ^ctx.current.id),
          set: [data_quality: answers]
        )

      {:ok, view, _html} = live(conn, ~p"/?quality=#{ctx.current.id}")
      assert has_element?(view, "#quality-link-#{ctx.current.id}", "2/#{@total}")
      refute has_element?(view, "#quality-criterion-removed_criterion")
      assert has_element?(view, "#quality-criteria > li:nth-child(#{@total})")
      refute has_element?(view, "#quality-criteria > li:nth-child(#{@total + 1})")
    end

    test "typing a search keeps the modal open", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/?quality=#{ctx.current.id}")
      view |> form("#search-form", %{"q" => "SET"}) |> render_change()
      assert_patch(view, ~p"/?#{[q: "SET", quality: ctx.current.id]}")
      assert has_element?(view, "#quality-modal")
    end
  end

  describe "the edit page" do
    test "saves an answer, and the catalog's score follows", %{conn: conn} = ctx do
      {:ok, catalog, _html} = live(conn, ~p"/")
      {:ok, view, _html} = live(conn, ~p"/versions/#{ctx.current.id}/edit")

      assert has_element?(view, "#edit_version_data_quality legend", "Data quality")
      assert has_element?(view, "#edit_version_data_quality-score", "2/#{@total}")

      for criterion <- DataQuality.criteria() do
        assert has_element?(
                 view,
                 "#edit_version_data_quality_#{criterion.key}",
                 criterion.question
               )
      end

      assert has_element?(view, "#edit_version_data_quality_in_one_piece_yes[checked]")
      assert has_element?(view, "#edit_version_data_quality_documented_no[checked]")
      assert has_element?(view, "#edit_version_data_quality_quality_checked_no[checked]")

      view
      |> form("#edit-form", edit_version: %{data_quality: %{"quality_checked" => "yes"}})
      |> render_change(%{"_target" => ["edit_version", "data_quality", "quality_checked"]})

      assert has_element?(view, "#edit-status", "Saved.")
      assert has_element?(view, "#edit_version_data_quality-saved")
      assert has_element?(view, "#edit_version_data_quality-score", "3/#{@total}")

      assert %{"quality_checked" => "yes", "documented" => "no"} =
               Repo.get!(DatasetVersion, ctx.current.id).data_quality

      assert has_element?(catalog, "#quality-link-#{ctx.current.id}", "3/#{@total}")
      assert has_element?(catalog, "#quality-link-#{ctx.current.id}[data-level='medium']")

      # Back to Unknown: the answer is removed.
      view
      |> form("#edit-form", edit_version: %{data_quality: %{"documented" => ""}})
      |> render_change(%{"_target" => ["edit_version", "data_quality", "documented"]})

      refute Map.has_key?(Repo.get!(DatasetVersion, ctx.current.id).data_quality, "documented")
      assert has_element?(view, "#edit_version_data_quality_documented_unknown[checked]")
      # One criterion Unknown: no count.
      assert has_element?(view, "#edit_version_data_quality-score", "?/#{@total}")
      assert has_element?(catalog, "#quality-link-#{ctx.current.id}", "?/#{@total}")
      assert_replayable()
    end

    test "the changelog shows the change readably", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/versions/#{ctx.current.id}/edit")

      view
      |> form("#edit-form", edit_version: %{data_quality: %{"quality_checked" => "yes"}})
      |> render_change(%{"_target" => ["edit_version", "data_quality", "quality_checked"]})

      {:ok, changelog, _html} = live(conn, ~p"/changelog")
      assert has_element?(changelog, "#changes .change-diff dt", "data_quality")
      assert has_element?(changelog, "#changes .quality-diff", "Quality-checked")
      assert has_element?(changelog, "#changes .quality-diff del", "No")
      assert has_element?(changelog, "#changes .quality-diff ins", "Yes")
      assert has_element?(changelog, "#changes .quality-diff ins", "3/#{@total}")
    end
  end

  test "the new dataset draft keeps the answers", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/datasets/new")

    view
    |> form("#dataset-form",
      dataset: %{
        name: "Half done",
        versions: %{"0" => %{"data_quality" => %{"documented" => "yes", "in_one_piece" => "no"}}}
      }
    )
    |> render_change()

    {:ok, index, _html} = live(conn, ~p"/")
    assert has_element?(index, "#add-dataset", "Continue adding dataset")

    {:ok, view, _html} = live(conn, ~p"/datasets/new")
    prefix = "#dataset_versions_0_data_quality"
    assert has_element?(view, "#{prefix}_documented_yes[checked]")
    assert has_element?(view, "#{prefix}_in_one_piece_no[checked]")
    assert has_element?(view, "#{prefix}_quality_checked_unknown[checked]")
    assert has_element?(view, "#{prefix}-score", "?/#{@total}")
  end

  test "a new version starts with the answers of its source", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/datasets/#{ctx.dataset.id}/versions/new")
    assert has_element?(view, "#version_data_quality_in_one_piece_yes[checked]")
    assert has_element?(view, "#version_data_quality_documented_no[checked]")

    view
    |> form("#version-form",
      version: %{version: "v3", release_date: "2026-09-01", cohort_size: "10"}
    )
    |> render_submit()

    version = Repo.get_by!(DatasetVersion, dataset_id: ctx.dataset.id, version: "v3")

    assert version.data_quality == ctx.current.data_quality
  end
end
