defmodule FGDataCatalogWeb.ThemeSwitchTest do
  # NOTE(Claude Opus 5.5 2026-11-17): the theme switch in the header; the
  # switching itself runs client-side (root.html.heex), so only its markup is
  # checked here.
  use FGDataCatalogWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "the header has the System, Light and Dark theme buttons", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, ~s(header #theme-switch[role="group"][phx-update="ignore"]))

    for choice <- ~w(system light dark) do
      assert has_element?(
               view,
               ~s(#theme-switch button#theme-#{choice}[type="button"][data-theme-choice="#{choice}"][aria-label])
             )
    end
  end
end
