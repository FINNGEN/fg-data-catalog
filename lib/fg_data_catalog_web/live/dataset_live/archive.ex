defmodule FGDataCatalogWeb.DatasetLive.Archive do
  @moduledoc """
  The archive: every archived dataset version, which the catalog no longer
  lists. For editors (signed-in users). A version can be put back in the
  catalog from here, as a Draft owned by whoever does it.
  """
  # NOTE(Claude 2026-11-05): added with archiving versions.
  use FGDataCatalogWeb, :live_view

  import FGDataCatalogWeb.CatalogComponents,
    only: [access_type_label: 1, no_value: 1, text_or_dash: 1]

  alias FGDataCatalog.Accounts.Scope
  alias FGDataCatalog.Catalog
  alias FGDataCatalog.Changelog

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="archive-page">
        <.link id="back-to-catalog" navigate={~p"/"} class="back-link">← Back to the catalog</.link>
        <h1 id="archive-title">Archived dataset versions</h1>

        <p :if={@versions == []} id="archive-empty" class="empty">Nothing is archived.</p>

        <%!-- NOTE(Claude 2026-11-06): no `.table-scroll` wrapper, which gave the
             table a scroll area of its own inside the scrolling page. --%>
        <table :if={@versions != []} id="archive-table" class="catalog-table">
          <caption class="visually-hidden">Archived dataset versions</caption>
          <thead>
            <tr>
              <th scope="col">Dataset</th>
              <th scope="col">Version</th>
              <th scope="col">Access type</th>
              <th scope="col">Release date</th>
              <th scope="col">Maintainer</th>
              <th scope="col">Archived</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={version <- @versions} id={"archived-version-#{version.id}"}>
              <th scope="row">
                {version.dataset.name}
                <%!-- NOTE(Claude 2026-11-06): a button, as it acts rather than navigates. --%>
                <%!-- NOTE(Claude 2026-11-16): see `Catalog.can?/3`. --%>
                <button
                  :if={Catalog.can?(@current_scope, :unarchive, version)}
                  type="button"
                  id={"unarchive-version-#{version.id}"}
                  class="unarchive-version link-button"
                  phx-click="unarchive"
                  phx-value-id={version.id}
                  aria-label={"Unarchive #{version.dataset.name} #{version.version}"}
                >
                  Unarchive
                </button>
              </th>
              <td><.text_or_dash text={version.version} /></td>
              <td><.text_or_dash text={access_type_label(version.access_type)} /></td>
              <td>
                <time data-local-date datetime={Date.to_iso8601(version.release_date)}>
                  {version.release_date}
                </time>
              </td>
              <td><.text_or_dash text={version.lead} /></td>
              <td>
                <%!-- NOTE(Claude 2026-11-16): `archived_at` is information only;
                     a version archived before it was kept may lack it. --%>
                <time :if={version.archived_at} datetime={DateTime.to_iso8601(version.archived_at)}>
                  {DateTime.to_date(version.archived_at)}
                </time>
                <.no_value :if={!version.archived_at} />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end

  # NOTE(Claude 2026-11-05): checked server-side, not only by hiding the link.
  @impl true
  def mount(_params, _session, socket) do
    # NOTE(Claude 2026-11-16): every editor, no longer admins only.
    if Scope.editor?(socket.assigns.current_scope) do
      if connected?(socket), do: Changelog.subscribe()

      {:ok,
       socket
       |> assign(:page_title, "Archive")
       |> assign_versions()}
    else
      {:ok,
       socket
       |> put_flash(:error, "The archive is not available.")
       |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("unarchive", %{"id" => id}, socket) do
    version = Enum.find(socket.assigns.versions, &(to_string(&1.id) == id))

    socket =
      with %{} <- version,
           {:ok, _} <- Catalog.unarchive_version(socket.assigns.current_scope, version) do
        assign_versions(socket)
      else
        _ -> put_flash(socket, :error, "You cannot unarchive that version.")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:catalog_changed, _change_set_id}, socket) do
    {:noreply, assign_versions(socket)}
  end

  defp assign_versions(socket), do: assign(socket, :versions, Catalog.list_archived_versions())
end
