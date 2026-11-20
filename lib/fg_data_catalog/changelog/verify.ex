defmodule FGDataCatalog.Changelog.Verify do
  @moduledoc """
  Checks that the changelog still fits the current tables, e.g. after a schema
  migration (see `FGDataCatalog.Changelog.Migration`).

    * The schemas' columns are the tables' columns.
    * Every recorded change names a tracked table; its keys are columns of that
      table; a full row (an insert's new values, a delete's old values) has all
      of them; its values are raw (no JSON arrays or objects) and load with the
      current schema.
    * Replaying every change forward from an empty database gives the current
      tables, and backward from the current tables gives an empty database.

  The replay alone would miss a row inserted and later deleted (it is in
  neither end state), hence the checks of each change.

  Run with `mix changelog.verify`, or in a release with
  `bin/fg_data_catalog eval "FGDataCatalog.Changelog.Verify.main()"`, on a copy
  of the database.
  """

  alias FGDataCatalog.Changelog
  alias FGDataCatalog.Changelog.Replay
  alias FGDataCatalog.Repo

  @doc "Returns `:ok`, or `{:error, issues}` with a message per issue."
  def run do
    tables = Map.new(Changelog.tracked(), &{&1.__schema__(:source), &1})
    columns = Map.new(tables, fn {table, _schema} -> {table, table_columns(table)} end)
    changes = Changelog.list_changes()

    issues =
      schema_issues(tables, columns) ++
        Enum.flat_map(changes, &change_issues(&1, tables, columns)) ++
        replay_issues(changes)

    if issues == [], do: :ok, else: {:error, issues}
  end

  @doc """
  Runs `run/0` with the repo started, prints the result and halts, with status
  1 on failure. For releases.
  """
  def main do
    Application.load(:fg_data_catalog)
    {:ok, result, _apps} = Ecto.Migrator.with_repo(Repo, fn _repo -> run() end)
    print(result)
    System.halt(if result == :ok, do: 0, else: 1)
  end

  @doc "Prints the result of `run/0`."
  def print(:ok), do: IO.puts("Changelog OK: #{database()} replays forward and backward.")

  def print({:error, issues}) do
    IO.puts(:stderr, "Changelog of #{database()}: #{length(issues)} issue(s)")
    for issue <- issues, do: IO.puts(:stderr, "  * " <> issue)
  end

  defp database, do: Repo.config()[:database]

  defp schema_issues(tables, columns) do
    for {table, schema} <- tables,
        expected = schema_columns(schema),
        expected != columns[table] do
      "table #{table} has columns #{inspect(columns[table])}, " <>
        "the schema #{inspect(schema)} #{inspect(expected)}"
    end
  end

  defp change_issues(change, tables, columns) do
    case Map.fetch(tables, change.table_name) do
      {:ok, schema} ->
        Enum.flat_map(recorded(change), fn {side, values} ->
          values_issues(change, side, values, schema, columns[change.table_name])
        end)

      :error ->
        [issue(change, "not a tracked table")]
    end
  end

  defp recorded(%{op: :insert, new_values: new}), do: [{:new, new}]
  defp recorded(%{op: :delete, old_values: old}), do: [{:old, old}]
  defp recorded(%{op: :update, old_values: old, new_values: new}), do: [old: old, new: new]

  defp values_issues(change, side, nil, _schema, _columns),
    do: [issue(change, "no #{side} values")]

  defp values_issues(change, side, values, schema, columns) do
    keys = values |> Map.keys() |> Enum.sort()
    unknown = keys -- columns
    missing = if change.op == :update, do: [], else: columns -- keys

    not_raw =
      for {key, value} <- values, is_list(value) or is_map(value), do: key

    [
      unknown != [] && "#{side} values: unknown columns #{Enum.join(unknown, ", ")}",
      missing != [] && "#{side} values: missing columns #{Enum.join(missing, ", ")}",
      not_raw != [] &&
        "#{side} values: not raw (JSON arrays or objects instead of JSON text): " <>
          Enum.join(Enum.sort(not_raw), ", "),
      (unknown == [] and not_raw == []) && load_issue(values, schema, side)
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&issue(change, &1))
  end

  defp load_issue(values, schema, side) do
    Repo.load(schema, values)
    nil
  rescue
    e -> "#{side} values do not load: #{Exception.message(e)}"
  end

  defp replay_issues(changes) do
    empty = Changelog.empty_snapshot()
    snapshot = Changelog.snapshot()

    [
      replay(fn -> Replay.forward(empty, changes) end, snapshot, "forward from empty"),
      replay(fn -> Replay.backward(snapshot, changes) end, empty, "backward from now")
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp replay(fun, expected, name) do
    case fun.() do
      ^expected -> nil
      state -> "replay #{name}: #{describe_difference(state, expected)}"
    end
  rescue
    e in Replay.Error -> "replay #{name}: #{Exception.message(e)}"
  end

  defp describe_difference(state, expected) do
    for {table, rows} <- expected,
        got = Map.get(state, table, %{}),
        id <- Enum.sort(Enum.uniq(Map.keys(rows) ++ Map.keys(got))),
        rows[id] != got[id] do
      "#{table} #{id}"
    end
    |> case do
      [] -> "states differ"
      rows -> "rows differ from the tables: " <> Enum.join(rows, ", ")
    end
  end

  defp issue(change, message),
    do: "change #{change.id} (#{change.op} #{change.table_name} #{change.record_id}): #{message}"

  defp table_columns(table) do
    %{rows: rows} = Repo.query!("SELECT name FROM pragma_table_info(?)", [table])
    rows |> List.flatten() |> Enum.sort()
  end

  defp schema_columns(schema) do
    schema.__schema__(:fields)
    |> Enum.map(&Atom.to_string(schema.__schema__(:field_source, &1)))
    |> Enum.sort()
  end
end
