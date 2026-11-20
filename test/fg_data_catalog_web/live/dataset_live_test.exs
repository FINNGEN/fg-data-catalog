defmodule FGDataCatalogWeb.DatasetLiveTest do
  # NOTE(Claude 2026-11-16): the catalog as a visitor sees it: not signed in.
  use FGDataCatalogWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import FGDataCatalog.CatalogFixtures

  @moduletag role: :visitor

  setup do
    dataset = dataset_fixture(%{name: "Kanta lab values"})
    old = version_fixture(dataset, %{version: "R13", release_date: ~D[2025-03-01]})
    current = version_fixture(dataset, %{version: "R14", release_date: ~D[2026-03-13]})

    draft =
      version_fixture(dataset, %{version: "R15", release_date: ~D[2026-09-01]}, state: :draft)

    %{dataset: dataset, old: old, current: current, draft: draft}
  end

  test "lists the current version with its previous versions hidden", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/")

    # NOTE(Claude 2026-11-06): checked on the row's elements, not the raw HTML.
    row = "#version-#{ctx.current.id}"
    assert has_element?(view, "#{row} th", "Kanta lab values")
    assert has_element?(view, "#{row} td", "Red account")
    assert has_element?(view, "#{row} .cohort-coverage", "500,000")
    # NOTE(Claude Opus 5.5 2026-11-17): the meter's gridlines, one per 100k.
    assert has_element?(view, "#{row} .cohort-coverage .meter-gridlines line")
    assert has_element?(view, "#{row} .year-coverage", "2013–2025")
    assert has_element?(view, "#{row} .dictionary-link", "2 variables")

    assert has_element?(view, "#version-#{ctx.current.id}.current-version:not([hidden])")
    assert has_element?(view, "#version-#{ctx.old.id}.previous-version[hidden]")
    assert has_element?(view, "#dataset-#{ctx.dataset.id} button.versions-toggle", "+1")

    # NOTE(Claude 2026-11-02): the toggle runs client-side, so check its JS targets the hidden rows.
    assert has_element?(
             view,
             ~s(button.versions-toggle[phx-click*="#dataset-#{ctx.dataset.id} .previous-version"])
           )

    refute has_element?(view, "#version-#{ctx.draft.id}")
  end

  # NOTE(Claude 2026-11-06): a previous version's row header names its dataset
  # for screen readers; visitors get no actions column.
  test "previous rows have a hidden row header, visitors no actions", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(
             view,
             "#version-#{ctx.old.id} th[scope='row'] .visually-hidden",
             "Kanta lab values"
           )

    refute has_element?(view, ".row-actions")
    refute has_element?(view, "thead th", "Actions")
  end

  # NOTE(Claude 2026-11-06): "Last updated" is the day of the latest change set.
  # NOTE(Claude 2026-11-06): empty fields show a dash, read as "No value".
  test "an empty field shows a dash", %{conn: conn} = ctx do
    ctx.current
    |> Ecto.Changeset.change(environments: [], tags: [], data_dictionary: [])
    |> FGDataCatalog.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/")
    row = "#version-#{ctx.current.id}"
    refute has_element?(view, "#{row} ul.tags")
    refute has_element?(view, "#{row} .dictionary-link")

    assert view
           |> element(row)
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query(".no-value")
           |> Enum.count() >= 3

    assert has_element?(view, "#{row} .no-value .visually-hidden", "No value")
  end

  # NOTE(Claude 2026-11-09): under the name, in the Dataset column, on the
  # current row only; nothing at all when the dataset has none.
  test "the description is shown under the dataset name", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "thead th", "Description")
    refute has_element?(view, ".dataset-description")

    ctx.dataset
    |> Ecto.Changeset.change(description: "Laboratory test results")
    |> FGDataCatalog.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(
             view,
             "#version-#{ctx.current.id} th[scope='row'] .dataset-description",
             "Laboratory test results"
           )

    refute has_element?(view, "#version-#{ctx.old.id} .dataset-description")
  end

  test "the OMOP column is headed OMOP-mapped", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "thead th", "OMOP-mapped")
    refute has_element?(view, "thead th", "In OMOP?")
  end

  test "shows the day of the latest change as last updated", %{conn: conn} do
    FGDataCatalog.Repo.update_all(FGDataCatalog.Changelog.ChangeSet,
      set: [inserted_at: ~U[2026-01-02 10:00:00Z]]
    )

    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, ~s(#last-updated time[datetime="2026-01-02"]))
  end

  # NOTE(Claude 2026-11-05): versions saved before list fields were sorted on
  # save keep their typed order in the database; they are sorted on display.
  test "shows list fields sorted, whatever their stored order", %{conn: conn} = ctx do
    FGDataCatalog.Repo.update_all(
      from(v in FGDataCatalog.Catalog.DatasetVersion, where: v.id == ^ctx.current.id),
      set: [tags: ["b", "C", "a"], formats: ["Flat file", "BigQuery DB table"]]
    )

    {:ok, view, _html} = live(conn, ~p"/")
    row = view |> element("#version-#{ctx.current.id}") |> render() |> LazyHTML.from_fragment()

    assert row |> LazyHTML.query("ul.tags li[data-tag]") |> Enum.map(&LazyHTML.text/1) == [
             "a",
             "b",
             "C"
           ]

    assert has_element?(view, "#version-#{ctx.current.id} td", "BigQuery DB table, Flat file")
  end

  test "opens and closes the data dictionary modal", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#dictionary-modal")

    view |> element("#version-#{ctx.current.id} a", "2 variables") |> render_click()
    assert_patch(view, ~p"/?dictionary=#{ctx.current.id}")
    assert has_element?(view, "dialog#dictionary-modal[phx-hook]", "FINNGENID")
    assert has_element?(view, "#dictionary-title", "Kanta lab values R14")

    view |> element("#dictionary-modal a.modal-close") |> render_click()
    assert_patch(view, ~p"/")
    refute has_element?(view, "#dictionary-modal")
  end

  test "ignores invalid or draft dictionary ids", %{conn: conn} = ctx do
    for id <- ["nope", "-1", to_string(ctx.draft.id)] do
      {:ok, view, _html} = live(conn, ~p"/?dictionary=#{id}")
      refute has_element?(view, "#dictionary-modal")
    end
  end

  # NOTE(Claude 2026-11-06): the server renders the dialog open, so that it shows
  # without JavaScript; its Close link is then a plain link.
  test "the dictionary modal is rendered open, with a Close link", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/?dictionary=#{ctx.current.id}")
    assert has_element?(view, "dialog#dictionary-modal[open] a.modal-close[href='/']")
  end

  # NOTE(Claude Opus 5.5 2026-11-17): the Maintainer column is for signed-in
  # users only.
  # NOTE(Claude Opus 5.5 2026-11-17): a web link opens in a new tab; a Unix
  # path is shown as code.
  test "the location is a link or a path", %{conn: conn} = ctx do
    ctx.current
    |> Ecto.Changeset.cast(%{locations: [%{value: "https://example.org/kanta"}]}, [])
    |> Ecto.Changeset.cast_embed(:locations)
    |> FGDataCatalog.Repo.update!()

    ctx.old
    |> Ecto.Changeset.cast(%{locations: [%{value: "/research/shared-data/kanta"}]}, [])
    |> Ecto.Changeset.cast_embed(:locations)
    |> FGDataCatalog.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(
             view,
             "#version-#{ctx.current.id} td.location a[href='https://example.org/kanta'][target='_blank']"
           )

    assert has_element?(
             view,
             "#version-#{ctx.old.id} td.location code.location-path",
             "/research/shared-data/kanta"
           )

    view |> form("#search-form", %{"q" => "shared-data"}) |> render_change()
    assert has_element?(view, "#version-#{ctx.current.id}")
    view |> form("#search-form", %{"q" => "library-blue"}) |> render_change()
    refute has_element?(view, "#version-#{ctx.current.id}")
  end

  # NOTE(Claude Opus 5.5 2026-11-19): a gs:// path is shown as code, like a
  # Unix path, not as a link.
  test "a gs:// location is a path", %{conn: conn} = ctx do
    ctx.current
    |> Ecto.Changeset.cast(%{locations: [%{value: "gs://example-bucket/kanta"}]}, [])
    |> Ecto.Changeset.cast_embed(:locations)
    |> FGDataCatalog.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(
             view,
             "#version-#{ctx.current.id} td.location code.location-path",
             "gs://example-bucket/kanta"
           )

    refute has_element?(view, "#version-#{ctx.current.id} td.location a")
  end

  # NOTE(Claude Opus 5.5 2026-11-17): a named link shows its name; a named path
  # shows its name, which reveals the full path.
  test "a named location shows its name", %{conn: conn} = ctx do
    ctx.current
    |> Ecto.Changeset.cast(
      %{locations: [%{value: "https://example.org/kanta", label: "Web page"}]},
      []
    )
    |> Ecto.Changeset.cast_embed(:locations)
    |> FGDataCatalog.Repo.update!()

    ctx.old
    |> Ecto.Changeset.cast(
      %{locations: [%{value: "/research/shared-data/kanta", label: "Team library"}]},
      []
    )
    |> Ecto.Changeset.cast_embed(:locations)
    |> FGDataCatalog.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(
             view,
             "#version-#{ctx.current.id} td.location a[href='https://example.org/kanta']",
             "Web page"
           )

    assert has_element?(
             view,
             "#version-#{ctx.old.id} td.location button.location-trigger",
             "Team library"
           )

    assert has_element?(
             view,
             "#version-#{ctx.old.id} td.location [popover] code.location-path",
             "/research/shared-data/kanta"
           )

    view |> form("#search-form", %{"q" => "team library"}) |> render_change()
    assert has_element?(view, "#version-#{ctx.current.id}")

    view |> form("#search-form", %{"q" => "research"}) |> render_change()
    assert has_element?(view, "#locations-#{ctx.old.id}.search-match")

    assert has_element?(
             view,
             "#locations-#{ctx.old.id}-copy-0[data-copy-location='locations-#{ctx.old.id}-path-0']"
           )
  end

  test "one popover lists every location and marks matches inside it", %{conn: conn} = ctx do
    ctx.current
    |> Ecto.Changeset.cast(
      %{
        locations: [
          %{value: "gs://fg-bucket/kanta", label: "Cloud"},
          %{value: "/research/sandbox/kanta", label: "Workspace"},
          %{value: "https://example.org/kanta", label: "Portal"}
        ]
      },
      []
    )
    |> Ecto.Changeset.cast_embed(:locations)
    |> FGDataCatalog.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/")
    id = "locations-#{ctx.current.id}"
    assert has_element?(view, "##{id}[popovertarget='#{id}-popover']", "3 locations")
    assert has_element?(view, "##{id}-popover[popover] ##{id}-path-0", "gs://fg-bucket/kanta")
    assert has_element?(view, "##{id}-popover ##{id}-path-1", "/research/sandbox/kanta")
    assert has_element?(view, "##{id}-popover a[href='https://example.org/kanta']")

    for query <- ["fg-bucket", "sandbox", "workspace"] do
      view |> form("#search-form", %{"q" => query}) |> render_change()
      assert has_element?(view, "##{id}.search-match")
    end
  end

  describe "the Maintainer column" do
    setup ctx do
      ctx.current |> Ecto.Changeset.change(lead: "Jane Doe") |> FGDataCatalog.Repo.update!()
      :ok
    end

    test "is hidden from visitors", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#version-#{ctx.current.id}")
      refute has_element?(view, "#maintainer-heading")
      refute has_element?(view, "td.maintainer")
    end

    @tag role: :editor
    test "is shown to signed-in users", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#maintainer-heading")
      assert has_element?(view, "#version-#{ctx.current.id} td.maintainer", "Jane Doe")
    end
  end

  describe "search" do
    setup ctx do
      other = dataset_fixture(%{name: "Drug purchases"})
      other_version = version_fixture(other, %{tags: ["Medication"], lead: "John Smith"})
      Map.merge(ctx, %{other: other, other_version: other_version})
    end

    test "typing filters datasets and is kept in the URL", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "#search-count", "of")

      view |> form("#search-form", %{"q" => "medication"}) |> render_change()
      assert_patch(view, ~p"/?q=medication")

      assert has_element?(view, "#dataset-#{ctx.other.id}")
      refute has_element?(view, "#dataset-#{ctx.dataset.id}")
      assert has_element?(view, "#search-count", "1 of 2 datasets")
      assert has_element?(view, "#search-form input[name='q'][value='medication']")
    end

    test "the description is searched and highlighted", %{conn: conn} = ctx do
      ctx.other
      |> Ecto.Changeset.change(description: "Prescription fills")
      |> FGDataCatalog.Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/?q=prescription")
      assert has_element?(view, "#dataset-#{ctx.other.id}")
      refute has_element?(view, "#dataset-#{ctx.dataset.id}")

      assert has_element?(
               view,
               "#version-#{ctx.other_version.id} th .dataset-description mark.search-match",
               "Prescription"
             )
    end

    # NOTE(Claude Opus 5.5 2026-11-17): as an editor, who sees (and searches)
    # the maintainer.
    @tag role: :editor
    test "every word must match, in any field", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/?q=drug+smith")
      assert has_element?(view, "#dataset-#{ctx.other.id}")

      {:ok, view, _html} = live(conn, ~p"/?q=kanta+smith")
      refute has_element?(view, "tbody.dataset")
      assert has_element?(view, "#no-results", "kanta smith")
    end

    # NOTE(Claude Opus 5.5 2026-11-17): the matches are marked, in any case.
    # As an editor, who sees (and searches) the maintainer.
    @tag role: :editor
    test "the matches are highlighted", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "mark.search-match")

      {:ok, view, _html} = live(conn, ~p"/?q=DRUG+smi")
      row = "#version-#{ctx.other_version.id}"
      assert has_element?(view, "#{row} th mark.search-match", "Drug")
      assert has_element?(view, "#{row} td mark.search-match", "Smi")
      assert has_element?(view, "#{row} th", "Drug purchases")
    end

    # NOTE(Claude Opus 5.5 2026-11-17): visitors do not see the maintainer,
    # so it does not match their search either.
    test "a visitor's search does not match the maintainer", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?q=smith")
      refute has_element?(view, "tbody.dataset")
      assert has_element?(view, "#no-results")
    end

    @tag role: :editor
    test "an editor's search matches the maintainer", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/?q=smith")
      assert has_element?(view, "#dataset-#{ctx.other.id}")
      refute has_element?(view, "#dataset-#{ctx.dataset.id}")
    end

    test "a blank search shows everything and leaves the URL clean", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/?q=drug")
      view |> form("#search-form", %{"q" => "  "}) |> render_change()
      assert_patch(view, ~p"/")
      assert has_element?(view, "#dataset-#{ctx.dataset.id}")
    end

    test "opening and closing the dictionary keeps the search", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/?q=kanta")

      view |> element("#version-#{ctx.current.id} a.dictionary-link") |> render_click()
      assert_patch(view, ~p"/?#{[dictionary: ctx.current.id, q: "kanta"]}")
      assert has_element?(view, "#dictionary-modal")

      view |> element("#dictionary-modal a.modal-close") |> render_click()
      assert_patch(view, ~p"/?q=kanta")
      refute has_element?(view, "#dictionary-modal")
    end

    # NOTE(Claude 2026-11-06): the sparklines' shared axis follows the rows shown.
    test "the header's year scale spans the rows shown", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      # 2013 to 2025: a label every two years, from 14.
      assert has_element?(view, "th .year-labels > span:first-child", "’14")

      FGDataCatalog.Repo.update_all(FGDataCatalog.Catalog.DatasetVersion,
        set: [coverage_start: 2000]
      )

      {:ok, view, _html} = live(conn, ~p"/?q=kanta")
      # 2000 to 2025: a label every five years, from 00.
      assert has_element?(view, "th .year-labels > span:first-child", "’00")
    end

    test "the search form works without JavaScript", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(
               view,
               "form#search-form[action='/'][method='get'] input[type='search'][name='q']"
             )
    end
  end

  # NOTE(Claude 2026-11-12): a click on a tag keeps the rows having it; a click
  # on a second tag, those having both.
  describe "tag filter" do
    setup ctx do
      drugs = dataset_fixture(%{name: "Drug purchases"})
      drugs_version = version_fixture(drugs, %{tags: ["Medication", "Registry"]})
      deaths = dataset_fixture(%{name: "Causes of death"})
      deaths_version = version_fixture(deaths, %{tags: ["Registry"]})

      Map.merge(ctx, %{
        drugs: drugs,
        drugs_version: drugs_version,
        deaths: deaths,
        deaths_version: deaths_version
      })
    end

    test "clicking tags narrows the rows, Clear resets them", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "#tag-filter")

      view
      |> element("#version-#{ctx.deaths_version.id} .tags li[data-tag='Registry'] a")
      |> render_click()

      assert_patch(view, ~p"/?#{%{"tags" => ["Registry"]}}")
      assert has_element?(view, "#dataset-#{ctx.drugs.id}")
      assert has_element?(view, "#dataset-#{ctx.deaths.id}")
      refute has_element?(view, "#dataset-#{ctx.dataset.id}")
      assert has_element?(view, "#search-count", "2 of 3 datasets")
      assert has_element?(view, "#tag-filter [data-tag-filter='Registry']")
      assert has_element?(view, "#version-#{ctx.drugs_version.id} li.is-tag-selected", "Registry")

      view
      |> element("#version-#{ctx.drugs_version.id} .tags li[data-tag='Medication'] a")
      |> render_click()

      assert_patch(view, ~p"/?#{%{"tags" => ["Registry", "Medication"]}}")
      assert has_element?(view, "#dataset-#{ctx.drugs.id}")
      refute has_element?(view, "#dataset-#{ctx.deaths.id}")
      assert has_element?(view, "#search-count", "1 of 3 datasets")

      view |> element("#clear-tag-filter") |> render_click()
      assert_patch(view, ~p"/")
      refute has_element?(view, "#tag-filter")
      assert has_element?(view, "#dataset-#{ctx.dataset.id}")
    end

    test "a tag of the filter is removed by a click", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/?#{%{"tags" => ["Registry", "Medication"]}}")

      view |> element("#tag-filter [data-tag-filter='Medication']") |> render_click()
      assert_patch(view, ~p"/?#{%{"tags" => ["Registry"]}}")
      assert has_element?(view, "#dataset-#{ctx.deaths.id}")
    end

    test "combines with the search, which keeps it", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/?#{%{"tags" => ["Registry"]}}")

      assert has_element?(
               view,
               "#search-form input[type='hidden'][name='tags[]'][value='Registry']"
             )

      view |> form("#search-form", %{"q" => "death"}) |> render_change()
      assert_patch(view, ~p"/?#{%{"q" => "death", "tags" => ["Registry"]}}")
      assert has_element?(view, "#dataset-#{ctx.deaths.id}")
      refute has_element?(view, "#dataset-#{ctx.drugs.id}")

      {:ok, view, _html} = live(conn, ~p"/?#{%{"q" => "kanta", "tags" => ["Registry"]}}")
      assert has_element?(view, "#no-results", "Registry")
    end
  end

  # NOTE(Claude 2026-11-10): the versions of a dataset share their sparklines'
  # height scale: the old version's busiest year (50) is half of the current
  # version's (100, see `valid_version_attrs/1`), so it is drawn half high.
  test "a dataset's sparklines share their height scale", %{conn: conn} = ctx do
    ctx.old
    |> Ecto.Changeset.change(
      yearly_counts: [%FGDataCatalog.Catalog.YearCount{year: 2013, count: 50}]
    )
    |> FGDataCatalog.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/")

    points =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#version-#{ctx.old.id} polygon.counts")
      |> LazyHTML.attribute("points")
      |> hd()

    assert points =~ ~r/ [\d.]+,10\.0 /
  end
end
