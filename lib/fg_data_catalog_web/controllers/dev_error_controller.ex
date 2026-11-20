defmodule FGDataCatalogWeb.DevErrorController do
  @moduledoc """
  NOTE(Claude Opus 5.5 2026-11-18): development only: shows the error page of
  a status code (`/dev/errors/404`, `/dev/errors/500`, …), as
  `Phoenix.Endpoint.RenderErrors` renders it in production. In development a
  real error shows Phoenix's debug page instead (`debug_errors: true`). Its
  route exists only with `dev_routes` (see the router).
  """
  use FGDataCatalogWeb, :controller

  def show(conn, %{"status" => status}) do
    case Integer.parse(status) do
      {status, ""} when status in 400..599 ->
        conn
        |> put_status(status)
        |> put_root_layout(html: {FGDataCatalogWeb.Layouts, :root})
        |> put_layout(false)
        |> put_view(html: FGDataCatalogWeb.ErrorHTML)
        |> render("#{status}.html", status: status, kind: :error, reason: nil, stack: [])

      _ ->
        conn
        |> put_status(:bad_request)
        |> text("Give a status code from 400 to 599, e.g. /dev/errors/404.")
    end
  end
end
