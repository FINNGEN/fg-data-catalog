defmodule FGDataCatalog.Changelog do
  @moduledoc """
  Writes to the catalog tables, each recorded in the changelog in the same
  transaction, so that the changelog can be replayed forward or backward to
  any earlier state (see `FGDataCatalog.Changelog.Replay`).

  Every write to a tracked table (`datasets`, `dataset_versions`) must go
  through `insert/2`, `update/2` or `delete/2` inside `transact/3`.

  ## Format

    * A `change_sets` row per user action: actor, action name, time.
    * A `changes` row per row written, ordered by `changes.id` (timestamps only
      have second precision). See `FGDataCatalog.Changelog.Change`.
    * Values are the raw SQLite column values, keyed by column name: JSON
      text for arrays and embeds (e.g. `tags`, `doc_links`), ISO 8601 text for
      dates and timestamps, integers, text, `null`. Writing them back verbatim
      restores the row exactly. Updates include `updated_at`.

  ## Schema migrations

  Replay and revert assume the current columns. A migration that adds,
  renames, drops or converts a column of a tracked table must rewrite the
  recorded values to match, with `FGDataCatalog.Changelog.Migration`, and
  then be checked with `mix changelog.verify` (`FGDataCatalog.Changelog.Verify`)
  on the dev database and on a copy of the production one.

  ## Not recorded

    * Schema migrations themselves: the recorded values are rewritten instead
      (see above).
    * Database cascades (`on_delete: :delete_all`): delete children through
      `delete/2` first. Only `Catalog.delete_draft_version/2` deletes catalog
      rows (NOTE(Claude-Opus-5.5 2026-11-26)): the draft version, then its
      dataset.
    * Unsaved "new dataset" drafts (`dataset_drafts`), which are not catalog data.
    * Users and their sessions (`users`, `users_tokens`), not catalog data either.
  """
  import Ecto.Query, warn: false

  alias FGDataCatalog.Repo
  alias FGDataCatalog.Catalog.{Dataset, DatasetVersion}
  alias FGDataCatalog.Changelog.{Change, ChangeSet}

  @tracked [Dataset, DatasetVersion]
  @pubsub FGDataCatalog.PubSub
  @topic "catalog"
  # NOTE(Claude Opus 5.5 2026-11-18): live edits merged on the changelog page,
  # see `edit_runs/1`. The action is the one of `Catalog.update_dataset_row/5`.
  @edit_action "edit row"
  @edit_run_seconds 60

  @doc "The tracked schemas, parents first."
  def tracked, do: @tracked

  @doc """
  Subscribes the caller to `{:catalog_changed, change_set_id}` messages, sent
  after each committed change set.
  """
  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, @topic)

  @doc """
  Runs `fun` in a transaction as one change set named `action`.

  `fun` receives the change set and returns `{:ok, result}` or `{:error, reason}`
  (which rolls everything back). A change set that ends up changing nothing is
  not kept.
  """
  def transact(action, actor, fun) when is_binary(action) and is_function(fun, 1) do
    result =
      Repo.transact(fn ->
        set = Repo.insert!(%ChangeSet{action: action, actor: actor})

        with {:ok, result} <- fun.(set) do
          if Repo.exists?(from c in Change, where: c.change_set_id == ^set.id) do
            {:ok, {result, set.id}}
          else
            Repo.delete!(set)
            {:ok, {result, nil}}
          end
        end
      end)

    case result do
      {:ok, {result, nil}} ->
        {:ok, result}

      {:ok, {result, set_id}} ->
        Phoenix.PubSub.broadcast(@pubsub, @topic, {:catalog_changed, set_id})
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Inserts a changeset's record and logs it, followed by the `has_many`
  children inserted with it (e.g. a dataset's first version).
  """
  def insert(%ChangeSet{} = set, %Ecto.Changeset{} = changeset) do
    with {:ok, record} <- Repo.insert(changeset) do
      log_insert_tree(set, record)
      {:ok, record}
    end
  end

  @doc """
  Updates a changeset's record and logs the changed columns.

  Nothing is logged if no column other than `updated_at` changes, and then
  `updated_at` is restored too: the row is left exactly as it was.
  """
  def update(%ChangeSet{} = set, %Ecto.Changeset{data: data} = changeset) do
    schema = data.__struct__
    old_row = raw_row(schema, data.id)

    with {:ok, record} <- Repo.update(changeset) do
      new_row = raw_row(schema, record.id)
      changed = for {column, value} <- new_row, old_row[column] != value, do: column

      if changed -- ["updated_at"] == [] do
        # NOTE(Claude 2026-11-03): e.g. embeds re-submitted unchanged: Ecto sees
        # a change, the stored row does not.
        restore_updated_at(schema, record.id, old_row["updated_at"])
        {:ok, %{record | updated_at: data.updated_at}}
      else
        log!(
          set,
          :update,
          schema,
          record.id,
          Map.take(old_row, changed),
          Map.take(new_row, changed)
        )

        {:ok, record}
      end
    end
  end

  @doc """
  Deletes a record and logs its last values. Children deleted by a database
  cascade are not logged: delete them first.
  """
  def delete(%ChangeSet{} = set, %{__struct__: schema, id: id} = record) do
    old_row = raw_row(schema, id)

    with {:ok, deleted} <- Repo.delete(record) do
      log!(set, :delete, schema, id, old_row, nil)
      {:ok, deleted}
    end
  end

  @doc """
  Undoes change set `set_id` as a new change set (named "revert change set
  #ID"), itself logged and revertible. Callers check who may (see
  `FGDataCatalog.Catalog.revert_change_set/2`).

  Its changes are undone newest first, each writing back the recorded raw
  values. Each must still apply: an updated row must still hold the values it
  was given (other columns may have changed since), an inserted row must be
  unchanged and have no children added since, a deleted row must not exist.
  Otherwise nothing is reverted.

  Returns `{:ok, new_set_id}`, or `{:error, reason}`: `:not_found`, `{:conflict,
  change}` (a change that no longer applies), or `{:database, message}`.

  `set_id` may also be the list of the change set ids of a run of live edits
  (see `edit_runs/1`), reverted as one change, from its last value back to its
  first, and named "revert change sets #FIRST to #LAST". The ids must form
  such a run, or nothing is reverted (`:not_found`).
  """
  # NOTE(Claude 2026-11-06): writes raw values back verbatim (see "Format"
  # above) rather than casting them through the schemas: JSON text and ISO
  # dates then round-trip exactly. A recorded column the schema no longer has
  # is a conflict.
  def revert([set_id], actor), do: revert(set_id, actor)

  # NOTE(Claude Opus 5.5 2026-11-18): a run of live edits, shown as one row of
  # the changelog page. One change is logged, not one per edit.
  def revert(set_ids, actor) when is_list(set_ids) do
    sets =
      from(s in ChangeSet, where: s.id in ^set_ids, order_by: s.id, preload: :changes)
      |> Repo.all()
      |> Enum.map(&set_changes/1)

    with true <- length(sets) == length(Enum.uniq(set_ids)) and length(sets) > 1,
         [[%Change{} = first] | _] <- sets,
         true <- run?(sets) do
      [last] = List.last(sets)
      merged = %Change{first | new_values: last.new_values}
      ids = "##{first.change_set_id} to ##{last.change_set_id}"
      revert_changes("revert change sets #{ids}", [merged], actor)
    else
      _ -> {:error, :not_found}
    end
  end

  def revert(set_id, actor) do
    case Repo.get(ChangeSet, set_id) |> Repo.preload(:changes) do
      %ChangeSet{changes: [_ | _] = changes} ->
        revert_changes("revert change set ##{set_id}", changes, actor)

      _ ->
        {:error, :not_found}
    end
  end

  defp revert_changes(action, changes, actor) do
    try do
      transact(action, actor, fn set ->
        changes
        |> Enum.sort_by(& &1.id, :desc)
        |> Enum.reduce_while({:ok, set.id}, fn change, ok ->
          case revert_change(set, change) do
            :ok -> {:cont, ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
      end)
    rescue
      e in [Exqlite.Error, Ecto.ConstraintError] ->
        {:error, {:database, Exception.message(e)}}
    end
  end

  defp revert_change(set, %Change{table_name: table, record_id: id} = change) do
    with {:ok, schema} <- tracked_schema(table, change),
         {:ok, columns} <- known_columns(schema, change) do
      current = raw_row_or_nil(schema, id)

      case change.op do
        :update ->
          keys = Map.keys(change.new_values) -- ["updated_at"]

          if current && Map.take(current, keys) == Map.take(change.new_values, keys) do
            values = Map.put(Map.take(change.old_values, keys), "updated_at", now_raw())
            raw_update(set, schema, id, values, columns)
          else
            {:error, {:conflict, change}}
          end

        :insert ->
          if current == change.new_values and not has_other_children?(schema, id) do
            raw_delete(set, schema, id, current)
          else
            {:error, {:conflict, change}}
          end

        :delete ->
          if current == nil do
            raw_insert(set, schema, id, change.old_values, columns)
          else
            {:error, {:conflict, change}}
          end
      end
    end
  end

  defp tracked_schema(table, change) do
    case Enum.find(@tracked, &(source(&1) == table)) do
      nil -> {:error, {:conflict, change}}
      schema -> {:ok, schema}
    end
  end

  # NOTE(Claude 2026-11-06): column name => atom, for the recorded columns,
  # which must all still exist.
  defp known_columns(schema, change) do
    columns = Map.new(columns(schema), &{Atom.to_string(&1), &1})
    recorded = Map.keys(change.old_values || %{}) ++ Map.keys(change.new_values || %{})

    if Enum.all?(recorded, &Map.has_key?(columns, &1)),
      do: {:ok, columns},
      else: {:error, {:conflict, change}}
  end

  # NOTE(Claude 2026-11-06): rows of `has_many` children (a dataset's versions)
  # would be deleted by the database cascade, unlogged: refuse instead. The
  # set's own children are deleted before their parent, being newer.
  defp has_other_children?(schema, id) do
    Enum.any?(schema.__schema__(:associations), fn name ->
      case schema.__schema__(:association, name) do
        %Ecto.Association.Has{related: related, related_key: key} ->
          Repo.exists?(from c in related, where: field(c, ^key) == ^id)

        _ ->
          false
      end
    end)
  end

  defp raw_update(set, schema, id, values, columns) do
    old_row = raw_row(schema, id)
    changes = Enum.map(values, fn {column, value} -> {Map.fetch!(columns, column), value} end)
    from(t in source(schema), where: t.id == ^id) |> Repo.update_all(set: changes)
    new_row = raw_row(schema, id)
    changed = for {column, value} <- new_row, old_row[column] != value, do: column
    log!(set, :update, schema, id, Map.take(old_row, changed), Map.take(new_row, changed))
    :ok
  end

  defp raw_delete(set, schema, id, old_row) do
    from(t in source(schema), where: t.id == ^id) |> Repo.delete_all()
    log!(set, :delete, schema, id, old_row, nil)
    :ok
  end

  defp raw_insert(set, schema, id, row, columns) do
    entry = Map.new(row, fn {column, value} -> {Map.fetch!(columns, column), value} end)
    Repo.insert_all(source(schema), [entry])
    log!(set, :insert, schema, id, nil, raw_row(schema, id))
    :ok
  end

  defp raw_row_or_nil(schema, id) do
    from(t in source(schema), where: t.id == ^id, select: map(t, ^columns(schema)))
    |> Repo.one()
    |> case do
      nil -> nil
      row -> stringify(row)
    end
  end

  # NOTE(Claude 2026-11-06): as Ecto stores `:utc_datetime` in SQLite.
  defp now_raw, do: DateTime.utc_now(:second) |> DateTime.to_iso8601()

  @doc """
  Reads every tracked table, as raw values, in the shape used by
  `FGDataCatalog.Changelog.Replay`: `%{table => %{id => row}}`.
  """
  def snapshot do
    Map.new(@tracked, fn schema ->
      rows =
        from(t in source(schema), select: map(t, ^columns(schema)))
        |> Repo.all()
        |> Map.new(fn row -> {row.id, stringify(row)} end)

      {source(schema), rows}
    end)
  end

  @doc "The snapshot of an empty database."
  def empty_snapshot, do: Map.new(@tracked, &{source(&1), %{}})

  @doc "All changes, oldest first, optionally only those after change `after_id`."
  def list_changes(after_id \\ 0) do
    from(c in Change, where: c.id > ^after_id, order_by: c.id) |> Repo.all()
  end

  # NOTE(Claude 2026-11-16): for the changelog page (editors only).
  @doc """
  Lists the latest changes, each with its `change_set`: grouped by change set,
  newest set first and a set's changes in order.

  Options: `:limit` (default 1000, a set may be cut short at the oldest end),
  `:before` (only changes with a smaller id, for older ones) and `:after` (only
  those with a larger id, the new ones).

  Filters (each optional): `:table` (a table name), `:record_id` (a row of that
  table, or of any table without `:table`), `:version` (a dataset version's id:
  the changes of that version and of its dataset's row, not of its other
  versions; also for a deleted version), `:dataset` (a dataset's id: the
  changes of its row and of all its versions, also of deleted ones),
  `:after_set` (only the changes of change sets newer than this one) and
  `:actor` (the change set's actor; `:none` for change sets without one).
  """
  def list_recent_changes(opts \\ []) do
    query =
      from c in Change,
        join: s in assoc(c, :change_set),
        as: :change_set,
        order_by: [desc: c.id],
        limit: ^Keyword.get(opts, :limit, 1000),
        preload: [change_set: s]

    query = if before = opts[:before], do: where(query, [c], c.id < ^before), else: query
    query = if after_id = opts[:after], do: where(query, [c], c.id > ^after_id), else: query
    # NOTE(Claude 2026-11-06): the filters of the changelog page.
    query = if table = opts[:table], do: where(query, [c], c.table_name == ^table), else: query
    query = if id = opts[:record_id], do: where(query, [c], c.record_id == ^id), else: query
    query = if id = opts[:version], do: where(query, ^version_changes(id)), else: query
    # NOTE(Claude-Opus-5.5 2026-11-26): what changed after a change set that
    # could not be reverted (see `revert/2`).
    query = if id = opts[:dataset], do: where(query, ^dataset_changes(id)), else: query

    query =
      if id = opts[:after_set], do: where(query, [c], c.change_set_id > ^id), else: query

    query =
      case opts[:actor] do
        nil -> query
        :none -> where(query, [change_set: s], is_nil(s.actor))
        actor -> where(query, [change_set: s], s.actor == ^actor)
      end

    query
    |> Repo.all()
    |> Enum.group_by(& &1.change_set_id)
    |> Map.values()
    |> Enum.map(&Enum.sort_by(&1, fn change -> change.id end))
    |> Enum.sort_by(fn [first | _] -> first.id end, :desc)
    |> List.flatten()
  end

  # NOTE(Claude Opus 5.5 2026-11-19): a catalog row shows its version's fields
  # and its dataset's name and description, so a version's history is both rows'.
  defp version_changes(version_id) do
    version = dynamic([c], c.table_name == "dataset_versions" and c.record_id == ^version_id)

    case version_dataset_id(version_id) do
      nil -> version
      id -> dynamic([c], ^version or (c.table_name == "datasets" and c.record_id == ^id))
    end
  end

  # NOTE(Claude-Opus-5.5 2026-11-26): a dataset's row and its versions, current
  # or deleted (a version's dataset is recorded when it is inserted or deleted,
  # and never changes).
  defp dataset_changes(dataset_id) do
    current = from(v in DatasetVersion, where: v.dataset_id == ^dataset_id, select: v.id)

    recorded =
      from(c in Change,
        where:
          c.table_name == "dataset_versions" and
            (fragment("json_extract(?, '$.dataset_id')", c.new_values) == ^dataset_id or
               fragment("json_extract(?, '$.dataset_id')", c.old_values) == ^dataset_id),
        distinct: true,
        select: c.record_id
      )

    version_ids = Enum.uniq(Repo.all(current) ++ Repo.all(recorded))

    dynamic(
      [c],
      (c.table_name == "datasets" and c.record_id == ^dataset_id) or
        (c.table_name == "dataset_versions" and c.record_id in ^version_ids)
    )
  end

  # NOTE(Claude Opus 5.5 2026-11-19): from the version's row, or from its
  # recorded values if it was deleted (a version's dataset never changes).
  defp version_dataset_id(version_id) do
    case Repo.one(from v in DatasetVersion, where: v.id == ^version_id, select: v.dataset_id) do
      nil -> recorded_version_dataset_id(version_id)
      id -> id
    end
  end

  defp recorded_version_dataset_id(version_id) do
    from(c in Change,
      where: c.table_name == "dataset_versions" and c.record_id == ^version_id,
      order_by: c.id
    )
    |> Repo.all()
    |> Enum.find_value(&List.first(recorded_dataset_id(&1)))
  end

  # NOTE(Claude Opus 5.5 2026-11-18): live edits save each debounced change as
  # a change set; the changelog page shows a run of them as one row.
  @doc """
  Groups the change sets of `changes` (as `list_recent_changes/1` returns
  them) into runs of live edits, for display: a list of runs, newest first,
  each a list of change sets (lists of changes) oldest first. A change set
  that is not part of a longer run is a run of its own.

  A change set continues a run if both are "edit row" change sets of a single
  change, an update of one and the same column (besides `updated_at`) of the
  same row, by the same actor, made at most #{@edit_run_seconds} seconds after
  the run's last one, with no other change set in between (in the whole log,
  whatever `changes` holds). The database keeps every change set.

  The run of the oldest change set is completed with its earlier change sets,
  older than `changes`, so that a page of the changelog never ends inside a
  run.
  """
  def edit_runs(changes) do
    sets = Enum.chunk_by(changes, & &1.change_set_id)
    ids = Enum.map(sets, &hd(&1).change_set_id)
    sizes = count_changes(ids)
    previous = previous_set_ids(ids)

    single? = fn [change | _] -> sizes[change.change_set_id] == 1 end

    continues? = fn [older | _] = older_set, [newer | _] = newer_set ->
      previous[newer.change_set_id] == older.change_set_id and single?.(older_set) and
        single?.(newer_set) and same_edit?(older_set, newer_set)
    end

    # Oldest first: each run is built newest set first, the runs newest first.
    runs =
      sets
      |> Enum.reverse()
      |> Enum.reduce([], fn set, runs ->
        case runs do
          [[newest | _] = run | rest] ->
            if continues?.(newest, set), do: [[set | run] | rest], else: [[set] | runs]

          [] ->
            [[set]]
        end
      end)

    case Enum.split(runs, -1) do
      {newer_runs, [oldest_run]} ->
        oldest_set = List.last(oldest_run)
        earlier = if single?.(oldest_set), do: earlier_edits(oldest_set, []), else: []
        Enum.map(newer_runs ++ [oldest_run ++ earlier], &Enum.reverse/1)

      {[], []} ->
        []
    end
  end

  # NOTE(Claude Opus 5.5 2026-11-18): the change sets that `newer` (a single
  # change) continues, newest first, read 100 at a time.
  defp earlier_edits([newer | _] = newer_set, acc) do
    batch =
      from(s in ChangeSet,
        where: s.id < ^newer.change_set_id,
        order_by: [desc: s.id],
        limit: 100,
        preload: :changes
      )
      |> Repo.all()
      |> Enum.map(&set_changes/1)

    walk_earlier(newer_set, batch, acc)
  end

  # The batch holds every change set before `newer_set`, newest first: each
  # one is the one just before the previous one.
  defp walk_earlier(_newer_set, [], acc), do: Enum.reverse(acc)

  defp walk_earlier(newer_set, [older_set | rest], acc) do
    cond do
      not same_edit?(older_set, newer_set) -> Enum.reverse(acc)
      rest == [] -> earlier_edits(older_set, [older_set | acc])
      true -> walk_earlier(older_set, rest, [older_set | acc])
    end
  end

  # NOTE(Claude Opus 5.5 2026-11-18): whether change sets `sets` (oldest first,
  # fully loaded) are a run of live edits, as `edit_runs/1` would group them.
  defp run?(sets) do
    previous = previous_set_ids(Enum.map(sets, &hd(&1).change_set_id))

    sets
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [[older] = older_set, [newer] = newer_set] ->
      previous[newer.change_set_id] == older.change_set_id and same_edit?(older_set, newer_set)
    end)
  end

  # Both are a single change (of their set, as far as the caller knows).
  defp same_edit?([%Change{} = older], [%Change{} = newer]) do
    a = older.change_set
    b = newer.change_set

    edit?(older) and edit?(newer) and a.actor == b.actor and
      older.table_name == newer.table_name and older.record_id == newer.record_id and
      edited_columns(older) == edited_columns(newer) and
      DateTime.diff(b.inserted_at, a.inserted_at) in 0..@edit_run_seconds
  end

  defp same_edit?(_older_set, _newer_set), do: false

  defp edit?(%Change{op: :update, change_set: %ChangeSet{action: @edit_action}} = change),
    do: length(edited_columns(change)) == 1

  defp edit?(_change), do: false

  defp edited_columns(change), do: Map.keys(change.new_values) -- ["updated_at"]

  # NOTE(Claude Opus 5.5 2026-11-18): the change set just before each of
  # `ids`, in the whole log. Not `id - 1`: empty change sets are deleted.
  defp previous_set_ids(ids) do
    from(s in ChangeSet,
      where: s.id in ^ids,
      select: {s.id, fragment("(SELECT max(p.id) FROM change_sets AS p WHERE p.id < ?)", s.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp set_changes(%ChangeSet{changes: changes} = set),
    do: Enum.map(changes, &%{&1 | change_set: set})

  # NOTE(Claude 2026-11-06): the catalog's "Last updated" date.
  @doc "When the latest change set was made (UTC), or `nil` if there is none."
  def last_changed_at do
    from(s in ChangeSet, select: max(s.inserted_at)) |> Repo.one()
  end

  @doc "The number of changes of each of the change sets `set_ids`, by id."
  def count_changes(set_ids) do
    from(c in Change,
      where: c.change_set_id in ^set_ids,
      group_by: c.change_set_id,
      select: {c.change_set_id, count(c.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "The distinct actors of the change sets, sorted; `nil` (none) first."
  def list_actors do
    from(s in ChangeSet, distinct: true, select: s.actor, order_by: s.actor) |> Repo.all()
  end

  @doc """
  A readable name for the row each change is about, keyed by `{table_name,
  record_id}`: the dataset's name, or the dataset's name and version for a
  version. Read from the current rows, or from the change's own values for a
  row that no longer exists.
  """
  # NOTE(Claude 2026-11-06): the changelog page showed `table #id` only.
  def row_names(changes) do
    ids = fn table ->
      for %{table_name: ^table, record_id: id} <- changes, uniq: true, do: id
    end

    versions =
      from(v in DatasetVersion,
        where: v.id in ^ids.("dataset_versions"),
        join: d in assoc(v, :dataset),
        select: {v.id, {d.name, v.version}}
      )
      |> Repo.all()
      |> Map.new()

    dataset_ids = ids.("datasets") ++ Enum.flat_map(changes, &recorded_dataset_id/1)

    datasets =
      from(d in Dataset, where: d.id in ^Enum.uniq(dataset_ids), select: {d.id, d.name})
      |> Repo.all()
      |> Map.new()

    Map.new(changes, fn change ->
      values = Map.merge(change.old_values || %{}, change.new_values || %{})
      key = {change.table_name, change.record_id}

      name =
        case change.table_name do
          "datasets" ->
            datasets[change.record_id] || values["name"]

          "dataset_versions" ->
            case versions[change.record_id] do
              {dataset, version} ->
                "#{dataset} #{version}"

              nil ->
                Enum.join(
                  Enum.reject([datasets[values["dataset_id"]], values["version"]], &is_nil/1),
                  " "
                )
            end

          _ ->
            nil
        end

      {key, name}
    end)
  end

  defp recorded_dataset_id(%{table_name: "dataset_versions"} = change) do
    values = Map.merge(change.old_values || %{}, change.new_values || %{})
    if id = values["dataset_id"], do: [id], else: []
  end

  defp recorded_dataset_id(_change), do: []

  @doc "The id of the latest change, or 0."
  def last_change_id do
    from(c in Change, select: max(c.id)) |> Repo.one() || 0
  end

  @doc "A row's raw column values, keyed by column name."
  def raw_row(schema, id) do
    from(t in source(schema), where: t.id == ^id, select: map(t, ^columns(schema)))
    |> Repo.one!()
    |> stringify()
  end

  defp log_insert_tree(set, %schema{} = record) do
    log!(set, :insert, schema, record.id, nil, raw_row(schema, record.id))

    for name <- schema.__schema__(:associations),
        %Ecto.Association.Has{cardinality: :many} <- [schema.__schema__(:association, name)],
        children = Map.fetch!(record, name),
        is_list(children),
        child <- children do
      log_insert_tree(set, child)
    end
  end

  defp log!(set, op, schema, id, old_values, new_values) do
    Repo.insert!(%Change{
      change_set_id: set.id,
      table_name: source(schema),
      record_id: id,
      op: op,
      old_values: old_values,
      new_values: new_values
    })
  end

  defp restore_updated_at(schema, id, value) do
    from(t in source(schema), where: t.id == ^id)
    |> Repo.update_all(set: [updated_at: value])
  end

  defp source(schema), do: schema.__schema__(:source)

  defp columns(schema) do
    Enum.map(schema.__schema__(:fields), &schema.__schema__(:field_source, &1))
  end

  defp stringify(row), do: Map.new(row, fn {k, v} -> {Atom.to_string(k), v} end)
end
