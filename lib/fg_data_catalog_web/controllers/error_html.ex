defmodule FGDataCatalogWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.

  NOTE(Claude Opus 5.5 2026-11-18): one page for every status code, inside the
  root layout (app.css, the favicon, the theme), with its own text for 404 and
  500 and the status message for the others (`page/1`). Its header is static:
  the title and the theme switch, no account and no flash, since a 404 for an
  unknown URL is rendered before the `:browser` pipeline (no session, no
  `current_scope`). It reads nothing from the database, which may be what
  failed.
  """
  use FGDataCatalogWeb, :html

  # NOTE(Claude Opus 5.5 2026-11-18): Phoenix calls `render("404.html", assigns)`
  # (`assigns` has `:status`, `:kind`, `:reason` and `:stack`, see
  # `Phoenix.Endpoint.RenderErrors`).
  def render(template, assigns) do
    {status, _format} = Integer.parse(template)

    assigns
    |> Map.put_new(:__changed__, nil)
    |> Map.merge(%{status: status, title: title(status), request_id: request_id()})
    |> page()
  end

  @doc """
  The page's heading, also its `<title>` (see `Layouts.page_title/1`).
  """
  def title(404), do: "Page not found"
  def title(500), do: "Something went wrong"
  def title(status), do: Plug.Conn.Status.reason_phrase(status)

  # NOTE(Claude Opus 5.5 2026-11-18): set by `Plug.RequestId` in the endpoint,
  # also in the log lines of the request (`metadata: [:request_id]`), so that a
  # reported 500 can be found in journald. Absent outside a request.
  defp request_id, do: Logger.metadata()[:request_id]

  defp page(assigns) do
    ~H"""
    <header class="site-header">
      <a href={~p"/"} id="site-title" class="site-title"><span
        class="title-bar"
        aria-hidden="true"
      ></span>FinnGen Data Catalog</a>
      <span class="site-account"></span>
      <Layouts.theme_switch />
    </header>

    <main class="site-main">
      <section id={"error-#{@status}"} class="error-page">
        <p class="error-status">Error {@status}</p>
        <h1>{@title}</h1>
        <.explanation status={@status} request_id={@request_id} />
        <p>
          <a id="error-home" href={~p"/"}>Go to the catalog</a>
        </p>
      </section>
    </main>
    """
  end

  attr :status, :integer, required: true
  attr :request_id, :string, default: nil

  defp explanation(%{status: 404} = assigns) do
    ~H"""
    <p>
      There is no page at this address. The link may be mistyped, or the page
      may have moved.
    </p>
    """
  end

  defp explanation(%{status: status} = assigns) when status >= 500 do
    ~H"""
    <p>
      The catalog could not show this page. Please try again in a moment.
    </p>
    <p :if={@request_id}>
      If it keeps happening, tell Vincent or ask on the FinnGen Slack,
      and give this reference: <code id="error-request-id">{@request_id}</code>.
    </p>
    <p :if={!@request_id}>
      If it keeps happening, tell Vincent or ask on the FinnGen Slack.
    </p>
    """
  end

  defp explanation(%{status: 403} = assigns) do
    ~H"""
    <p>
      The catalog refused this request. If you were filling in a form, your
      session may have expired: reload the page and try again.
    </p>
    """
  end

  defp explanation(assigns) do
    ~H"""
    <p>The catalog could not handle this request. Go back and try again.</p>
    """
  end
end
