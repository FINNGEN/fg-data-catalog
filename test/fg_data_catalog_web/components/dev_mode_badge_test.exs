defmodule FGDataCatalogWeb.DevModeBadgeTest do
  # NOTE(Claude-Opus-5.5 2026-11-25): the "DEVELOPER VERSION" badge is compiled
  # in only with `dev_routes` (config/dev.exs), which the test environment
  # does not set, so here it must be absent, as in production.
  use FGDataCatalogWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "the header has no developer version badge outside development", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "header #account")
    refute has_element?(view, "#dev-mode")
  end
end
