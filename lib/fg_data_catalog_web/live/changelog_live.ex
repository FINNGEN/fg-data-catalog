defmodule FGDataCatalogWeb.ChangelogLive do
  @moduledoc """
  The changelog: every change made to the catalog, newest first, grouped by the
  user action (change set) that made it. For editors (signed-in users), who
  may all revert any change set.

  Consecutive live edits of one field of a row by one person are shown as one
  row, from the first value to the last, and reverted as one (see
  `FGDataCatalog.Changelog.edit_runs/1`); the database keeps each of them.

  The list can be filtered by table, row and actor, kept in the URL
  (`?table=dataset_versions&row=12&actor=...`), or by version and actor
  (`?version=12&actor=...`): a version's History link in the catalog opens it
  filtered to that version and its dataset's row, whose name and description
  the catalog row shows too (`version` replaces `table` and `row`).

  `?dataset=5` filters to a dataset's row and all its versions, and `after=345`
  to the change sets newer than #345: a revert refused because a row changed
  since links to these later changes (`after` with `table` and `row`, or with
  `dataset`, whose versions may block the revert of its insertion).
  """
  # NOTE(Claude 2026-11-05): added as a readable view of `FGDataCatalog.Changelog`.
  use FGDataCatalogWeb, :live_view

  alias FGDataCatalog.Accounts.Scope
  alias FGDataCatalog.Catalog
  alias FGDataCatalog.Catalog.{DataQuality, DatasetVersion}
  alias FGDataCatalog.Changelog

  @page_size 1000
  # NOTE(Claude 2026-11-05): long values (a data dictionary, say) are cut here.
  @max_value_length 120
  # NOTE(Claude 2026-11-06): the tables that can be filtered on, and their names.
  @tables [{"datasets", "Datasets"}, {"dataset_versions", "Versions"}]
  # NOTE(Claude 2026-11-06): the `actor` URL parameter of change sets without
  # an actor (scripts), shown as "system".
  @no_actor "-"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="changelog-page">
        <.link id="back-to-catalog" navigate={~p"/"} class="back-link">← Back to the catalog</.link>
        <h1 id="changelog-title">Changelog</h1>

        <.form
          for={@filter_form}
          id="changelog-filters"
          class="filters"
          phx-change="filter"
          phx-submit="filter"
        >
          <%!-- NOTE(Claude Opus 5.5 2026-11-19): a version's filter spans two
               tables, so there is no table to choose. --%>
          <.input
            :if={!@filters.version}
            field={@filter_form[:table]}
            type="select"
            label="Table"
            prompt="All tables"
            options={table_options()}
          />
          <.input
            field={@filter_form[:actor]}
            type="select"
            label="Actor"
            prompt="All actors"
            options={@actor_options}
          />
          <input :if={@filters.row} type="hidden" name="row" value={@filters.row} />
          <input :if={@filters.version} type="hidden" name="version" value={@filters.version} />
          <input :if={@filters.dataset} type="hidden" name="dataset" value={@filters.dataset} />
          <input :if={@filters.after} type="hidden" name="after" value={@filters.after} />
          <p :if={@filters.row} id="row-filter" class="row-filter">
            Row: {@row_filter_name || "##{@filters.row}"}
            <.link id="clear-row-filter" patch={changelog_path(%{@filters | row: nil})}>
              Show all rows
            </.link>
          </p>
          <p :if={@filters.version} id="row-filter" class="row-filter">
            Row: {@row_filter_name || "Version ##{@filters.version}"} and its dataset
            <.link id="clear-row-filter" patch={changelog_path(%{@filters | version: nil})}>
              Show all rows
            </.link>
          </p>
          <%!-- NOTE(Claude-Opus-5.5 2026-11-26): a dataset and its versions. --%>
          <p :if={@filters.dataset} id="row-filter" class="row-filter">
            Row: {@row_filter_name || "Dataset ##{@filters.dataset}"} and its versions
            <.link id="clear-row-filter" patch={changelog_path(%{@filters | dataset: nil})}>
              Show all rows
            </.link>
          </p>
          <%!-- NOTE(Claude-Opus-5.5 2026-11-26): the changes made after a change
               set (see `revert_error/2`). --%>
          <p :if={@filters.after} id="after-filter" class="row-filter">
            After change set #{@filters.after}
            <.link id="clear-after-filter" patch={changelog_path(%{@filters | after: nil})}>
              Show older changes too
            </.link>
          </p>
          <.link
            :if={@filtered?}
            id="clear-filters"
            patch={~p"/changelog"}
          >
            Clear filters
          </.link>
        </.form>

        <p :if={@empty?} id="changelog-empty" class="empty">
          {if @filtered?, do: "No changes match these filters.", else: "Nothing has changed yet."}
        </p>

        <table id="changelog-table" class="catalog-table changelog-table">
          <caption class="visually-hidden">Changes, newest first</caption>
          <thead>
            <tr>
              <th scope="col">When (UTC)</th>
              <th scope="col">Actor</th>
              <th scope="col">Action</th>
              <th scope="col">Row</th>
              <th scope="col">Operation</th>
              <th scope="col">Changes</th>
            </tr>
          </thead>
          <%!-- NOTE(Claude 2026-11-05): one row per change. The change set's time,
                 actor and action are shown on its first row only. --%>
          <tbody id="changes" phx-update="stream">
            <tr
              :for={{id, row} <- @streams.changes}
              id={id}
              class={["change", row.first? && "first-of-set"]}
            >
              <td>
                <time :if={row.first?} datetime={DateTime.to_iso8601(row.set.inserted_at)}>
                  {Calendar.strftime(row.set.inserted_at, "%Y-%m-%d %H:%M:%S")}
                </time>
                <%!-- NOTE(Claude Opus 5.5 2026-11-18): a run of live edits, shown
                     at its last one. --%>
                <small :if={row.run_size > 1} class="edit-run">
                  {row.run_size} saves since
                  <time datetime={DateTime.to_iso8601(row.run_from)}>
                    {Calendar.strftime(row.run_from, "%H:%M:%S")}
                  </time>
                </small>
              </td>
              <td>
                <%!-- NOTE(Claude 2026-11-06): filters the list to this actor. --%>
                <.link
                  :if={row.first?}
                  class="actor-filter"
                  patch={changelog_path(%{@filters | actor: actor_param(row.set.actor)})}
                >
                  {row.set.actor || "system"}
                </.link>
              </td>
              <td>
                {row.first? && row.set.action}
                <%!-- NOTE(Claude 2026-11-06): undoes the whole change set, as a new
                     one (see `FGDataCatalog.Changelog.revert/2`). --%>
                <%!-- NOTE(Claude Opus 5.5 2026-11-18): a run of live edits is
                     reverted whole; not at all if it changed nothing. --%>
                <button
                  :if={row.first? and not row.no_net_change?}
                  type="button"
                  id={"revert-set-#{row.set.id}"}
                  class="revert-set"
                  phx-click="revert"
                  phx-value-ids={Enum.join(row.set_ids, ",")}
                  data-confirm={revert_confirm(row)}
                  aria-label={revert_label(row)}
                >
                  <.icon name="hero-arrow-uturn-left" /> Revert
                </button>
              </td>
              <td>
                <%!-- NOTE(Claude 2026-11-06): the row's name, which filters the list
                     to its history; its table and id below. --%>
                <.link
                  class="row-filter-link"
                  patch={
                    changelog_path(%{
                      @filters
                      | table: row.change.table_name,
                        row: row.change.record_id,
                        version: nil,
                        dataset: nil
                    })
                  }
                >
                  {row.name || "##{row.change.record_id}"}
                </.link>
                <small class="row-ref">
                  {table_label(row.change.table_name)} #{row.change.record_id}
                </small>
              </td>
              <td>{row.change.op}</td>
              <td>
                <%= if row.change.op == :update do %>
                  <p :if={row.no_net_change?} class="no-net-change">No net change</p>
                  <dl class="change-diff">
                    <%= for {field, new} <- sorted(row.change.new_values), field != "updated_at" do %>
                      <dt>{field}</dt>
                      <%!-- NOTE(Claude 2026-11-16): the data quality answers, one line
                           per changed criterion, and the score. --%>
                      <%!-- NOTE(Claude Opus 5.5 2026-11-18): and the fields marked
                           Not applicable, one line per field that changed. --%>
                      <%= if field in ["data_quality", "not_applicable", "locations"] do %>
                        <dd
                          :for={line <- field_diff(field, row.change.old_values[field], new)}
                          class={["quality-diff", field == "locations" && "location-history"]}
                        >
                          {line.label}: <del>{line.old}</del> → <ins>{line.new}</ins>
                        </dd>
                      <% else %>
                        <dd>
                          <del>{format_value(row.change.old_values[field])}</del>
                          → <ins>{format_value(new)}</ins>
                        </dd>
                      <% end %>
                    <% end %>
                  </dl>
                <% else %>
                  <details>
                    <summary>Values</summary>
                    <dl class="change-diff">
                      <%= for {field, value} <- sorted(row.change.new_values || row.change.old_values) do %>
                        <dt>{field}</dt>
                        <dd class={field == "locations" && "location-history"}>
                          {if field == "locations",
                            do: format_locations(value),
                            else: format_value(value)}
                        </dd>
                      <% end %>
                    </dl>
                  </details>
                <% end %>
              </td>
            </tr>
          </tbody>
        </table>

        <button :if={@more?} id="load-more" type="button" phx-click="load-more">
          Load older changes
        </button>
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
       |> assign(:page_title, "Changelog")}
    else
      {:ok,
       socket
       |> put_flash(:error, "The changelog is not available.")
       |> push_navigate(to: ~p"/")}
    end
  end

  # NOTE(Claude 2026-11-06): the filters come from the URL; each change of them
  # reloads the newest page of changes.
  @impl true
  def handle_params(params, _uri, socket) do
    if Scope.editor?(socket.assigns.current_scope),
      do: load(socket, params),
      else: {:noreply, socket}
  end

  defp load(socket, params) do
    filters = parse_filters(params)

    {changes, more?} = fetch(filters, limit: @page_size + 1)
    runs = Changelog.edit_runs(changes)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:filtered?, filter_params(filters) != %{})
     |> assign(:filter_form, to_form(filter_params(filters)))
     |> assign(:actor_options, actor_options())
     |> assign(:row_filter_name, row_filter_name(filters, changes))
     |> assign(:more?, more?)
     |> assign(:empty?, changes == [])
     |> assign(:newest_id, max_id(changes, Changelog.last_change_id()))
     |> assign(:oldest_id, min_id(runs))
     |> stream(:changes, rows(runs), reset: true)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters =
      params
      |> Map.take(["table", "actor", "row", "version", "dataset", "after"])
      |> parse_filters()

    {:noreply, push_patch(socket, to: changelog_path(filters))}
  end

  # NOTE(Claude Opus 5.5 2026-11-18): the ids of a change set, or of the change
  # sets of a run of live edits ("12,13,14").
  def handle_event("revert", %{"ids" => ids}, socket) do
    socket =
      case parse_ids(ids) do
        {:ok, ids} ->
          case Catalog.revert_change_set(socket.assigns.current_scope, ids) do
            {:ok, _set_id} -> put_flash(socket, :info, reverted_text(ids))
            {:error, reason} -> put_flash(socket, :error, revert_error(reason, ids))
          end

        :error ->
          put_flash(socket, :error, revert_error(:not_found, []))
      end

    {:noreply, socket}
  end

  def handle_event("load-more", _params, socket) do
    {changes, more?} =
      fetch(socket.assigns.filters, limit: @page_size + 1, before: socket.assigns.oldest_id)

    runs = Changelog.edit_runs(changes)

    {:noreply,
     socket
     |> assign(:more?, more?)
     |> assign(:oldest_id, min_id(runs) || socket.assigns.oldest_id)
     |> stream(:changes, rows(runs))}
  end

  # NOTE(Claude Opus 5.5 2026-11-18): a new live edit may continue the run of
  # the top row, which `Changelog.edit_runs/1` then returns whole: its row keeps
  # its DOM id (its first change's), so it is replaced.
  @impl true
  def handle_info({:catalog_changed, _change_set_id}, socket) do
    new =
      Changelog.list_recent_changes(
        filter_opts(socket.assigns.filters) ++ [after: socket.assigns.newest_id, limit: 10_000]
      )

    {:noreply,
     socket
     |> assign(:empty?, socket.assigns.empty? and new == [])
     |> assign(:newest_id, max_id(new, socket.assigns.newest_id))
     |> assign(:actor_options, actor_options())
     |> stream(:changes, new |> Changelog.edit_runs() |> rows() |> Enum.reverse(), at: 0)}
  end

  # NOTE(Claude 2026-11-06): says how many changes are undone, as the filters
  # may hide some of them (a change set is reverted whole).
  defp revert_confirm(%{run_size: 1, set: set, set_size: count}) do
    when_text = Calendar.strftime(set.inserted_at, "%Y-%m-%d %H:%M")
    changes = if count == 1, do: "its 1 change", else: "all its #{count} changes"

    "Revert \"#{set.action}\" of #{when_text}, #{changes}, shown or not?"
  end

  # NOTE(Claude Opus 5.5 2026-11-18): a run of live edits.
  defp revert_confirm(%{run_size: count, set: set, run_from: from}) do
    from_text = Calendar.strftime(from, "%Y-%m-%d %H:%M:%S")
    to_text = Calendar.strftime(set.inserted_at, "%H:%M:%S")

    "Revert the #{count} saves of \"#{set.action}\" from #{from_text} to #{to_text}, " <>
      "back to the value before the first?"
  end

  defp revert_label(%{run_size: 1, set: set}),
    do: "Revert change set #{set.id}: #{set.action}"

  defp revert_label(%{run_size: count, set: set}),
    do: "Revert #{count} saves: #{set.action}"

  defp reverted_text([id]), do: "Reverted change set ##{id}."

  defp reverted_text(ids),
    do: "Reverted #{length(ids)} saves, change sets ##{List.first(ids)} to ##{List.last(ids)}."

  defp parse_ids(text) do
    ids =
      text
      |> String.split(",")
      |> Enum.map(&Integer.parse/1)

    if ids != [] and Enum.all?(ids, &match?({_id, ""}, &1)),
      do: {:ok, ids |> Enum.map(&elem(&1, 0)) |> Enum.sort()},
      else: :error
  end

  # NOTE(Claude 2026-11-06): why a change set could not be reverted.
  # NOTE(Claude-Opus-5.5 2026-11-26): "the later changes" links to the changes
  # of the row made after the change set(s) `ids`, without the other filters
  # (they may hide some): of a dataset's versions too, as a version added since
  # blocks the revert of the dataset's insertion. Safe HTML, not a template: a
  # flash may be serialized.
  defp revert_error({:conflict, change}, ids) do
    name = Changelog.row_names([change])[{change.table_name, change.record_id}]

    assigns = %{
      row: name || "#{table_label(change.table_name)} ##{change.record_id}",
      path: later_changes_path(change, List.last(ids))
    }

    rendered = ~H"""
    Not reverted: {@row} has changed since. Revert the
    <.link id="later-changes" patch={@path}>later changes</.link>
    first.
    """

    {:safe, Phoenix.HTML.Safe.to_iodata(rendered)}
  end

  defp revert_error(:unauthorized, _ids), do: "Only editors can revert changes."
  defp revert_error(:not_found, _ids), do: "That change set was not found."
  defp revert_error({:database, _message}, _ids), do: "Not reverted: the database refused it."

  defp later_changes_path(change, set_id) do
    filters = %{table: nil, row: nil, version: nil, dataset: nil, after: set_id, actor: nil}

    case change.table_name do
      "datasets" -> changelog_path(%{filters | dataset: change.record_id})
      table -> changelog_path(%{filters | table: table, row: change.record_id})
    end
  end

  # NOTE(Claude 2026-11-06): unknown tables and malformed rows are ignored.
  # NOTE(Claude Opus 5.5 2026-11-19): and malformed versions; a version replaces
  # the table and the row (it spans two tables).
  # NOTE(Claude-Opus-5.5 2026-11-26): so does a dataset (with its versions);
  # `after` goes with any of them.
  defp parse_filters(params) do
    table = params["table"]
    table = if table in Enum.map(@tables, &elem(&1, 0)), do: table
    row = parse_id(params["row"])
    version = parse_id(params["version"])
    dataset = parse_id(params["dataset"])
    after_set = parse_id(params["after"])

    actor =
      case params["actor"] do
        actor when actor in [nil, ""] -> nil
        actor -> actor
      end

    cond do
      version -> %{table: nil, row: nil, version: version, dataset: nil}
      dataset -> %{table: nil, row: nil, version: nil, dataset: dataset}
      true -> %{table: table, row: row, version: nil, dataset: nil}
    end
    |> Map.merge(%{after: after_set, actor: actor})
  end

  defp parse_id(text) do
    case Integer.parse(to_string(text || "")) do
      {id, ""} when id > 0 -> id
      _ -> nil
    end
  end

  defp filter_params(filters) do
    filters
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn {key, value} -> {Atom.to_string(key), to_string(value)} end)
  end

  defp changelog_path(filters) do
    case filter_params(filters) do
      params when params == %{} -> ~p"/changelog"
      params -> ~p"/changelog?#{params}"
    end
  end

  defp filter_opts(filters) do
    [
      table: filters.table,
      record_id: filters.row,
      version: filters.version,
      dataset: filters.dataset,
      after_set: filters.after,
      actor: if(filters.actor == @no_actor, do: :none, else: filters.actor)
    ]
  end

  defp actor_param(nil), do: @no_actor
  defp actor_param(actor), do: actor

  defp actor_options do
    Enum.map(Changelog.list_actors(), fn
      nil -> {"system", @no_actor}
      actor -> {actor, actor}
    end)
  end

  defp table_options, do: Enum.map(@tables, fn {table, label} -> {label, table} end)

  defp table_label(table) do
    case List.keyfind(@tables, table, 0) do
      {_table, label} -> label
      nil -> table
    end
  end

  # NOTE(Claude Opus 5.5 2026-11-19): the filtered row's name, also for a
  # version's filter. Read from the row, or from the listed changes of a deleted
  # one (`nil` if none is listed).
  defp row_filter_name(%{version: id}, changes) when is_integer(id),
    do: row_name("dataset_versions", id, changes)

  defp row_filter_name(%{dataset: id}, changes) when is_integer(id),
    do: row_name("datasets", id, changes)

  defp row_filter_name(%{table: table, row: id}, changes)
       when is_binary(table) and is_integer(id),
       do: row_name(table, id, changes)

  defp row_filter_name(_filters, _changes), do: nil

  defp row_name(table, id, changes) do
    row = %{table_name: table, record_id: id, old_values: nil, new_values: nil}
    listed = Enum.filter(changes, &(&1.table_name == table and &1.record_id == id))
    name = Changelog.row_names([row | listed])[{table, id}]

    if name in [nil, ""], do: nil, else: name
  end

  # NOTE(Claude 2026-11-05): the changes of a page, and whether older ones remain.
  defp fetch(filters, opts) do
    changes = Changelog.list_recent_changes(filter_opts(filters) ++ opts)
    full? = length(changes) > @page_size
    # The extra change is the one with the smallest id.
    changes =
      if full?,
        do: Enum.reject(changes, &(&1.id == min_id(changes))),
        else: changes

    {changes, full?}
  end

  # NOTE(Claude Opus 5.5 2026-11-18): the table rows of `runs` (see
  # `Changelog.edit_runs/1`, in display order): a row per change of a change
  # set, the first flagged, or a single row for a run of live edits, from its
  # first old value to its last new one, with the id of its first change.
  defp rows(runs) do
    changes = List.flatten(runs)
    names = Changelog.row_names(changes)
    sizes = changes |> Enum.map(& &1.change_set_id) |> Enum.uniq() |> Changelog.count_changes()

    Enum.flat_map(runs, fn
      [[first | _] = chunk] ->
        Enum.map(
          chunk,
          &%{
            id: &1.id,
            set: &1.change_set,
            change: &1,
            first?: &1 == first,
            set_size: Map.get(sizes, &1.change_set_id, 0),
            set_ids: [&1.change_set_id],
            run_size: 1,
            run_from: &1.change_set.inserted_at,
            no_net_change?: false,
            name: names[{&1.table_name, &1.record_id}]
          }
        )

      [[first] | _] = run ->
        [last] = List.last(run)
        merged = %{first | new_values: last.new_values, change_set: last.change_set}

        [
          %{
            id: first.id,
            set: last.change_set,
            change: merged,
            first?: true,
            set_size: 1,
            set_ids: Enum.map(run, fn [change] -> change.change_set_id end),
            run_size: length(run),
            run_from: first.change_set.inserted_at,
            no_net_change?:
              Map.delete(merged.old_values, "updated_at") ==
                Map.delete(merged.new_values, "updated_at"),
            name: names[{first.table_name, first.record_id}]
          }
        ]
    end)
  end

  defp max_id([], default), do: default
  defp max_id(changes, _default), do: changes |> Enum.map(& &1.id) |> Enum.max()

  # NOTE(Claude Opus 5.5 2026-11-18): of changes, or of runs of change sets.
  defp min_id([]), do: nil
  defp min_id(changes), do: changes |> List.flatten() |> Enum.map(& &1.id) |> Enum.min()

  defp sorted(values), do: values |> Kernel.||(%{}) |> Enum.sort()

  # NOTE(Claude 2026-11-16): the recorded answers are JSON text (see
  # `FGDataCatalog.Changelog`); a changed criterion per line, then the score.
  # Answers to criteria no longer in the list are not shown.
  defp quality_diff(old, new) do
    old = decode_answers(old)
    new = decode_answers(new)

    lines =
      for {label, old_answer, new_answer} <- DataQuality.diff(old, new),
          do: %{
            label: label,
            old: DataQuality.answer_label(old_answer),
            new: DataQuality.answer_label(new_answer)
          }

    lines ++
      [%{label: "Score", old: DataQuality.score_text(old), new: DataQuality.score_text(new)}]
  end

  defp field_diff("data_quality", old, new), do: quality_diff(old, new)
  defp field_diff("not_applicable", old, new), do: not_applicable_diff(old, new)

  defp field_diff("locations", old, new),
    do: [%{label: "Locations", old: format_locations(old), new: format_locations(new)}]

  defp format_locations(json) do
    case decode_names(json) do
      [] ->
        "∅"

      entries ->
        Enum.map_join(entries, "\n", fn
          %{"label" => label, "value" => value} when is_binary(label) -> "#{label} (#{value})"
          %{"value" => value} -> value
        end)
    end
  end

  # NOTE(Claude Opus 5.5 2026-11-18): the recorded names are JSON text (see
  # `DatasetVersion.not_applicable_fields/0`); a line per field marked or
  # unmarked.
  @not_applicable_labels %{
    "years_coverage" => "Years coverage",
    "cohort_size" => "Cohort coverage"
  }

  defp not_applicable_diff(old, new) do
    old = decode_names(old)
    new = decode_names(new)

    for {name, _virtual} <- DatasetVersion.not_applicable_fields(),
        name in old != name in new,
        do: %{
          label: Map.get(@not_applicable_labels, name, name),
          old: applicable_label(name in old),
          new: applicable_label(name in new)
        }
  end

  defp applicable_label(true), do: "Not applicable"
  defp applicable_label(false), do: "Applicable"

  defp decode_names(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, names} when is_list(names) -> names
      _ -> []
    end
  end

  defp decode_names(_value), do: []

  defp decode_answers(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{} = answers} -> answers
      _ -> %{}
    end
  end

  defp decode_answers(_value), do: %{}

  defp format_value(nil), do: "∅"

  defp format_value(value) do
    text = if is_binary(value), do: value, else: inspect(value)

    if String.length(text) > @max_value_length,
      do: String.slice(text, 0, @max_value_length) <> "…",
      else: text
  end
end
