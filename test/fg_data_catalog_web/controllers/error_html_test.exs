defmodule FGDataCatalogWeb.ErrorHTMLTest do
  use FGDataCatalogWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  # NOTE(Claude Opus 5.5 2026-11-18): the error pages (`FGDataCatalogWeb.ErrorHTML`).
  defp render_page(status) do
    FGDataCatalogWeb.ErrorHTML
    |> render_to_string("#{status}", "html", status: status, kind: :error)
    |> LazyHTML.from_fragment()
  end

  defp text(document, selector) do
    document |> LazyHTML.query(selector) |> LazyHTML.text() |> String.trim()
  end

  test "renders 404.html" do
    page = render_page(404)

    assert text(page, "#error-404 h1") == "Page not found"
    assert LazyHTML.attribute(LazyHTML.query(page, "#error-home"), "href") == ["/"]
    refute Enum.any?(LazyHTML.query(page, "#account, #sign-in"))
  end

  test "renders 500.html with the request id" do
    Logger.metadata(request_id: "F-test-request-id")
    page = render_page(500)

    assert text(page, "#error-500 h1") == "Something went wrong"
    assert text(page, "#error-request-id") == "F-test-request-id"
    assert text(page, "#error-500") =~ "Vincent"
  end

  test "renders 500.html without a request id" do
    Logger.metadata(request_id: nil)
    page = render_page(500)

    assert Enum.any?(LazyHTML.query(page, "#error-500"))
    refute Enum.any?(LazyHTML.query(page, "#error-request-id"))
  end

  test "renders other status codes with their status message" do
    assert text(render_page(403), "#error-403 h1") == "Forbidden"
    assert text(render_page(413), "#error-413 h1") == "Request Entity Too Large"
  end

  @tag role: :visitor
  test "an unknown path gets the 404 page in the root layout", %{conn: conn} do
    page = conn |> get("/no-such-page") |> html_response(404) |> LazyHTML.from_document()

    assert Enum.any?(LazyHTML.query(page, "#error-404"))
    assert Enum.any?(LazyHTML.query(page, ~s(link[rel="stylesheet"])))
    assert Enum.any?(LazyHTML.query(page, "#theme-switch"))
    assert text(page, "title") == "Page not found · FinnGen Data Catalog"
  end
end
