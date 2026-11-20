defmodule FGDataCatalog.Changelog.Migration do
  @moduledoc """
  Rewrites the recorded changelog values in a schema migration, so that the
  changelog stays replayable and revertable after a column of a tracked table
  (`datasets`, `dataset_versions`) is added, renamed, dropped or changes type.

  Call these from the migration's `up` and `down` (never from `change`, which
  would run them forward again on rollback), after the table change.
  Each rewrites every `changes` row of `table`, in Elixir, and saves only those
  that changed. Pending migration commands are flushed first, so the table
  change is done before the changelog is read.

      alias FGDataCatalog.Changelog.Migration, as: ChangelogMigration

      def up do
        alter table(:dataset_versions), do: add(:reviewer, :string)
        ChangelogMigration.add_key("dataset_versions", "reviewer", nil)
      end

      def down do
        alter table(:dataset_versions), do: remove(:reviewer)
        ChangelogMigration.drop_key("dataset_versions", "reviewer")
      end

  Then check the result with `mix changelog.verify` (see
  `FGDataCatalog.Changelog.Verify`).

  ## Rules

    * Full rows (an insert's `new_values`, a delete's `old_values`) hold every
      column of the table: a new column is added to them, a dropped one removed.
      Updates hold only the columns they changed: a new column is not added.
    * Values are raw SQLite values: text, numbers, `nil`. Arrays and embeds are
      JSON text (`"[\\"a\\"]"`), never JSON arrays or objects. Every rewrite
      raises if it would record a list or a map.

  ## Stability

  Past migrations call these functions whenever a database is migrated from
  scratch (`mix ecto.reset`), so they only use table names, column names and
  raw values, never the current schemas. Do not change what an existing
  function does: add a new one instead.
  """

  # NOTE(Claude Opus 5.5 2026-11-17): the helpers that the development
  # migrations wrote inline, gathered here (those migrations were squashed into
  # `create_schema` before the first deploy).

  @doc """
  Renames the recorded key `from` to `to`, in every change of `table` (full
  rows and updates, old and new values). Where `from` is absent, nothing
  changes.

  Options:

    * `:map`: a function applied to each value (default: the value itself),
      e.g. to look up a foreign key.
    * `:repo`: the repo, outside a migration (tests).
  """
  def rename_key(table, from, to, opts \\ []) do
    map = Keyword.get(opts, :map, & &1)
    rewrite(table, &rename_in(&1, from, to, map), opts)
  end

  @doc """
  Removes the recorded key `key` from every change of `table`. An update that
  changed only `key` keeps its other values (at least `updated_at`).
  """
  def drop_key(table, key, opts \\ []) do
    rewrite(table, &drop_in(&1, key), opts)
  end

  @doc """
  Adds the key `key` to every recorded full row of `table` (inserts and
  deletes), with the value `default`, or `default.(row)` if it is a function of
  the recorded row (as it was before this rewrite). Updates are not changed.
  Raises if `key` is already recorded.

  The value is what the migration gives the existing rows of the table, e.g.
  the column's default.
  """
  def add_key(table, key, default, opts \\ []) do
    rewrite(table, &add_in(&1, key, default), opts)
  end

  @doc """
  Rewrites every recorded change of `table`, oldest first, with `fun`.

  `fun` receives the change as a map (`:id`, `:record_id`, `:op` as an atom,
  `:old_values`, `:new_values`, the values as decoded maps or `nil`) and returns
  it with new `:old_values` and `:new_values`. A 2-arity `fun` also receives the
  row as it was before the change, following the recorded changes from its
  insert (`nil` before its insert, after its delete, or if its insert is not
  in the changelog). The row is built from the values as recorded before this
  rewrite.

  For conversions the other helpers do not cover, e.g. a change of type (each
  recorded date becoming its year) or a value that depends on the row's past (a
  new `state` computed from the `status` and `archived_at` the row had then).
  """
  def rewrite(table, fun, opts \\ []) when is_function(fun, 1) or is_function(fun, 2) do
    repo = migration_repo(opts)

    %{rows: rows} =
      repo.query!(
        """
        SELECT id, record_id, op, old_values, new_values FROM changes
        WHERE table_name = ? ORDER BY id
        """,
        [table]
      )

    Enum.reduce(rows, %{}, fn [id, record_id, op, old_json, new_json], rows_before ->
      change = %{
        id: id,
        record_id: record_id,
        op: String.to_existing_atom(op),
        old_values: decode(old_json),
        new_values: decode(new_json)
      }

      row = Map.get(rows_before, record_id)
      new_change = if is_function(fun, 2), do: fun.(change, row), else: fun.(change)
      check_raw!(new_change)

      if {new_change.old_values, new_change.new_values} != {change.old_values, change.new_values} do
        repo.query!("UPDATE changes SET old_values = ?, new_values = ? WHERE id = ?", [
          encode(new_change.old_values),
          encode(new_change.new_values),
          id
        ])
      end

      Map.put(rows_before, record_id, apply_change(row, change))
    end)

    :ok
  end

  # NOTE(Claude Opus 5.5 2026-11-17): the pure rewrites of one change, used by
  # the helpers above (and tested on their own).

  @doc false
  def rename_in(change, from, to, map \\ & &1) do
    rename = fn
      nil ->
        nil

      values ->
        case Map.pop(values, from, :missing) do
          {:missing, values} ->
            values

          {value, values} ->
            if Map.has_key?(values, to),
              do: raise(ArgumentError, "change #{change.id} already records #{inspect(to)}")

            Map.put(values, to, map.(value))
        end
    end

    %{change | old_values: rename.(change.old_values), new_values: rename.(change.new_values)}
  end

  @doc false
  def drop_in(change, key) do
    drop = fn
      nil -> nil
      values -> Map.delete(values, key)
    end

    %{change | old_values: drop.(change.old_values), new_values: drop.(change.new_values)}
  end

  @doc false
  def add_in(%{op: :insert} = change, key, default),
    do: %{change | new_values: put_new!(change, change.new_values, key, default)}

  def add_in(%{op: :delete} = change, key, default),
    do: %{change | old_values: put_new!(change, change.old_values, key, default)}

  def add_in(%{op: :update} = change, _key, _default), do: change

  defp put_new!(change, row, key, default) do
    if Map.has_key?(row, key),
      do: raise(ArgumentError, "change #{change.id} already records #{inspect(key)}")

    value = if is_function(default, 1), do: default.(row), else: default
    Map.put(row, key, value)
  end

  # NOTE(Claude Opus 5.5 2026-11-17): the row before the next change, from the
  # change as recorded (see `rewrite/3`).
  defp apply_change(_row, %{op: :insert, new_values: values}), do: values
  defp apply_change(nil, %{op: :update}), do: nil
  defp apply_change(row, %{op: :update, new_values: values}), do: Map.merge(row, values)
  defp apply_change(_row, %{op: :delete}), do: nil

  defp check_raw!(change) do
    for values <- [change.old_values, change.new_values],
        values != nil,
        {key, value} <- values,
        is_list(value) or is_map(value) do
      raise ArgumentError,
            "change #{change.id}: #{inspect(key)} would be recorded as #{inspect(value)}; " <>
              "record arrays and embeds as JSON text (Jason.encode!/1)"
    end

    :ok
  end

  # NOTE(Claude Opus 5.5 2026-11-17): inside a migration, `execute` and the like
  # are only queued: flush them, so that the table change is done first (as
  # `flush()` in the migration would).
  defp migration_repo(opts) do
    case Keyword.fetch(opts, :repo) do
      {:ok, repo} ->
        repo

      :error ->
        Ecto.Migration.Runner.flush()
        Ecto.Migration.Runner.repo()
    end
  end

  defp decode(nil), do: nil
  defp decode(json), do: Jason.decode!(json)
  defp encode(nil), do: nil
  defp encode(map), do: Jason.encode!(map)
end
