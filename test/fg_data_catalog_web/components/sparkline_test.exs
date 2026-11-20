defmodule FGDataCatalogWeb.SparklineTest do
  # NOTE(Claude 2026-11-06): the Years coverage sparklines, on a shared time axis.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias FGDataCatalog.Catalog.YearCount
  alias FGDataCatalogWeb.CatalogComponents

  defp version(attrs) do
    Map.merge(%{coverage_start: nil, coverage_end: nil, yearly_counts: []}, attrs)
  end

  defp render_svg(attrs) do
    (&CatalogComponents.sparkline/1)
    |> render_component(attrs)
    |> LazyHTML.from_fragment()
  end

  defp attribute(doc, selector, name) do
    doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
  end

  describe "year_domain/1" do
    test "spans the coverage dates and count years of every version" do
      datasets = [
        %{versions: [version(%{coverage_start: 2013, coverage_end: 2020})]},
        %{versions: [version(%{yearly_counts: [%YearCount{year: 1999, count: 1}]})]},
        %{versions: [version(%{})]}
      ]

      assert CatalogComponents.year_domain(datasets) == {1999, 2020}
    end

    test "is nil without any year" do
      assert CatalogComponents.year_domain([%{versions: [version(%{})]}]) == nil
    end
  end

  # NOTE(Claude 2026-11-06): the ticks of the header's year scale.
  doctest CatalogComponents, only: [year_ticks: 1, year_labels: 1], import: true

  # NOTE(Claude 2026-11-06): the search's matches, marked in the catalog.
  doctest CatalogComponents, only: [highlight: 2], import: true

  describe "year_ticks/1" do
    test "every year on a short axis" do
      assert CatalogComponents.year_ticks({2018, 2020}) == [2018, 2019, 2020, 2021]
    end

    test "round steps on a long axis, with its ends" do
      assert CatalogComponents.year_ticks({1953, 2023}) ==
               [1953, 1960, 1970, 1980, 1990, 2000, 2010, 2020, 2024]
    end

    test "a single year" do
      assert CatalogComponents.year_ticks({2020, 2020}) == [2020, 2021]
    end
  end

  describe "year_axis/1" do
    test "draws a tick per tick year, at its place on the shared axis" do
      doc =
        (&CatalogComponents.year_axis/1)
        |> render_component(domain: {2000, 2009})
        |> LazyHTML.from_fragment()

      assert attribute(doc, "line.year-tick", "x1") ==
               ["0.0", "20.0", "40.0", "60.0", "80.0", "100.0"]

      # NOTE(Claude 2026-11-06): two-digit labels on the round ticks.
      labels = LazyHTML.query(doc, ".year-labels > span")
      assert Enum.map(labels, &LazyHTML.text/1) == ["’00", "’02", "’04", "’06", "’08"]
      assert LazyHTML.attribute(labels, "style") |> hd() == "left: 0.0%"
    end

    test "renders nothing without a domain" do
      assert render_component(&CatalogComponents.year_axis/1, domain: nil) =~ ~r/^\s*$/
    end

    # NOTE(Claude 2026-11-09): the year 2000 stands out on the scale.
    test "bolds the label of the year 2000" do
      doc =
        (&CatalogComponents.year_axis/1)
        |> render_component(domain: {1998, 2023})
        |> LazyHTML.from_fragment()

      assert doc |> LazyHTML.query(".year-labels > .year-2000") |> LazyHTML.text() == "’00"
    end
  end

  # NOTE(Claude 2026-11-09): the year scale's ticks carried onto the plots.
  # NOTE(Claude Opus 5.5 2026-11-17): across the whole axis, over its grey
  # background, no longer only within the coverage band.
  describe "sparkline/1 gridlines" do
    test "a gridline per tick across the axis, beyond the coverage band" do
      doc =
        render_svg(
          counts: [%YearCount{year: 2001, count: 3}],
          coverage_start: 2001,
          coverage_end: 2012,
          domain: {1998, 2023}
        )

      assert attribute(doc, "line.gridline", "x1") ==
               ["7.69", "26.92", "46.15", "65.38", "84.62"]
    end

    test "the year 2000's marked" do
      doc =
        render_svg(counts: [], coverage_start: 1999, domain: {1998, 2023})

      assert attribute(doc, "line.gridline", "x1") ==
               ["7.69", "26.92", "46.15", "65.38", "84.62"]

      assert attribute(doc, "line.gridline-2000", "x1") == ["7.69"]
    end

    test "also without a coverage band, on the axis' background" do
      doc = render_svg(counts: [%YearCount{year: 2001, count: 3}], domain: {1998, 2023})

      assert attribute(doc, "line.gridline", "x1") ==
               ["7.69", "26.92", "46.15", "65.38", "84.62"]

      assert attribute(doc, "rect.axis-band", "width") == ["100"]
    end
  end

  # NOTE(Claude 2026-11-09): the ticks of the header's cohort scale.
  doctest CatalogComponents,
    only: [cohort_ticks: 1, cohort_labels: 1, cohort_gridlines: 1],
    import: true

  describe "cohort_axis/1" do
    test "draws a tick per 100,000, labelling 0 and 500k" do
      doc =
        (&CatalogComponents.cohort_axis/1)
        |> render_component(max: 500_000)
        |> LazyHTML.from_fragment()

      assert attribute(doc, ".axis-ticks line", "x1") ==
               ["0", "0.0", "20.0", "40.0", "60.0", "80.0", "100.0"]

      labels = LazyHTML.query(doc, ".axis-labels > span")
      assert Enum.map(labels, &LazyHTML.text/1) == ["0", "500k"]
    end
  end

  describe "sparkline/1" do
    test "draws one step per year on the shared axis, gaps dropping to zero" do
      counts = [%YearCount{year: 2001, count: 5}, %YearCount{year: 2003, count: 10}]
      doc = render_svg(counts: counts, domain: {2000, 2004})

      # Five years of 20 units each: 2001 is 20..40 at half height, 2003 60..80 at full.
      assert attribute(doc, "polygon.counts", "points") == [
               "20.0,20.0 20.0,10.0 40.0,10.0 40.0,20.0 60.0,20.0 60.0,0.0 80.0,0.0 80.0,20.0"
             ]
    end

    test "a single year is drawn too" do
      doc = render_svg(counts: [%YearCount{year: 2000, count: 3}], domain: {2000, 2000})

      assert attribute(doc, "polygon.counts", "points") == [
               "0.0,20.0 0.0,0.0 100.0,0.0 100.0,20.0"
             ]
    end

    test "the coverage band spans the coverage period, its last day included" do
      doc =
        render_svg(
          counts: [],
          coverage_start: 2001,
          coverage_end: 2002,
          domain: {2000, 2003}
        )

      assert attribute(doc, "rect.coverage-band", "x") == ["25.0"]
      assert attribute(doc, "rect.coverage-band", "width") == ["50.0"]
      assert doc |> LazyHTML.query("polygon") |> Enum.count() == 0
    end

    test "renders nothing without years" do
      assert render_component(&CatalogComponents.sparkline/1, counts: [], domain: nil) =~
               ~r/^\s*$/
    end
  end

  # NOTE(Claude 2026-11-10): the versions of a dataset share a height scale.
  describe "sparkline/1 y_max" do
    test "heights are relative to y_max when given" do
      doc =
        render_svg(counts: [%YearCount{year: 2000, count: 5}], domain: {2000, 2000}, y_max: 10)

      assert attribute(doc, "polygon.counts", "points") == [
               "0.0,20.0 0.0,10.0 100.0,10.0 100.0,20.0"
             ]
    end
  end

  # NOTE(Claude 2026-11-10): the decade chunks and their tooltips.
  doctest CatalogComponents, only: [decade_chunks: 2], import: true

  describe "sparkline/1 decade chunks" do
    test "a chunk per decade of the version's years, with its total" do
      doc =
        render_svg(
          counts: [
            %YearCount{year: 1998, count: 1},
            %YearCount{year: 1999, count: 1_000},
            %YearCount{year: 2005, count: 2},
            %YearCount{year: 2010, count: 1}
          ],
          coverage_start: 1990,
          domain: {1990, 2011}
        )

      assert attribute(doc, "rect.chunk", "data-tip-years") == [
               "1990–1999",
               "2000–2009",
               "2010–2011"
             ]

      assert attribute(doc, "rect.chunk", "data-tip-points") ==
               ["data points: 1,001", "data points: 2", "data points: 1"]

      # NOTE(Claude 2026-11-10): from the coverage start (1990) to the axis'
      # end (2011), as the coverage period has no end.
      assert attribute(doc, "rect.chunk", "x") == ["0.0", "45.45", "90.91"]
      assert attribute(doc, "rect.chunk", "width") == ["45.45", "45.45", "9.09"]
      assert attribute(doc, "svg", "aria-label") |> hd() =~ "2000–2009: data points: 2"
    end

    test "a chunk of the coverage period without counts says so" do
      doc =
        render_svg(
          counts: [%YearCount{year: 2001, count: 3}],
          coverage_start: 1998,
          coverage_end: 2001,
          domain: {1998, 2001}
        )

      assert attribute(doc, "rect.chunk", "data-tip-years") == ["1998–1999", "2000–2001"]

      assert attribute(doc, "rect.chunk", "data-tip-points") == [
               "data points: 0",
               "data points: 3"
             ]
    end

    test "none without counts" do
      doc = render_svg(counts: [], coverage_start: 1999, domain: {1998, 2023})
      assert attribute(doc, "rect.chunk", "x") == []
    end
  end
end
