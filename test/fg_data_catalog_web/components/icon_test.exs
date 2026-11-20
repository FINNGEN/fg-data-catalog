defmodule FGDataCatalogWeb.IconTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import FGDataCatalogWeb.CoreComponents, only: [icon: 1]

  # NOTE(Claude 2026-11-06): `<.icon>` renders the Heroicon inline, from deps/heroicons.
  test "renders an inline SVG icon" do
    doc =
      render_component(&icon/1, name: "hero-x-mark", class: "extra") |> LazyHTML.from_fragment()

    assert [svg] = doc |> LazyHTML.query("svg.icon.hero-x-mark.extra") |> Enum.to_list()
    assert LazyHTML.attribute(svg, "viewBox") == ["0 0 24 24"]
    assert LazyHTML.attribute(svg, "aria-hidden") == ["true"]
    assert svg |> LazyHTML.query("path") |> Enum.count() > 0
  end

  test "raises for an icon that is not embedded" do
    assert_raise ArgumentError, ~r/unknown icon/, fn ->
      render_component(&icon/1, name: "hero-not-an-icon")
    end
  end
end
