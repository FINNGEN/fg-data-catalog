defmodule FGDataCatalog.Changelog.Replay do
  @moduledoc """
  Replays changelog entries on an in-memory copy of the catalog tables, without
  touching the database.

  A state is `%{table_name => %{id => row}}`, with rows as raw column values
  keyed by column name (as `FGDataCatalog.Changelog.snapshot/0` returns it).
  Changes are `FGDataCatalog.Changelog.Change` structs, or maps with the same
  keys.

  Replay is strict: each change is checked against the state it applies to
  (e.g. an update's old values must match the row), and a mismatch raises
  `FGDataCatalog.Changelog.Replay.Error`, as it means the log is incomplete or
  is being applied to the wrong state.
  """

  defmodule Error do
    defexception [:message]
  end

  @doc "Applies `changes` in order, oldest first."
  def forward(state, changes) do
    changes |> Enum.sort_by(& &1.id) |> Enum.reduce(state, &apply_forward/2)
  end

  @doc "Undoes `changes` in reverse order, newest first."
  def backward(state, changes) do
    changes |> Enum.sort_by(& &1.id, :desc) |> Enum.reduce(state, &apply_backward/2)
  end

  defp apply_forward(%{op: op} = change, state) do
    case op(op) do
      :insert -> put_new_row!(state, change, change.new_values)
      :update -> update_row!(state, change, change.old_values, change.new_values)
      :delete -> remove_row!(state, change, change.old_values)
    end
  end

  defp apply_backward(%{op: op} = change, state) do
    case op(op) do
      :insert -> remove_row!(state, change, change.new_values)
      :update -> update_row!(state, change, change.new_values, change.old_values)
      :delete -> put_new_row!(state, change, change.old_values)
    end
  end

  defp put_new_row!(state, change, row) do
    if get_row(state, change), do: fail!(change, "row already exists")
    put_row(state, change, row)
  end

  defp remove_row!(state, change, expected) do
    if get_row(state, change) != expected, do: fail!(change, "row does not match")
    %{state | change.table_name => Map.delete(state[change.table_name], change.record_id)}
  end

  defp update_row!(state, change, expected, values) do
    row = get_row(state, change) || fail!(change, "row does not exist")
    if Map.take(row, Map.keys(expected)) != expected, do: fail!(change, "row does not match")
    put_row(state, change, Map.merge(row, values))
  end

  defp get_row(state, change),
    do: state |> Map.get(change.table_name, %{}) |> Map.get(change.record_id)

  defp put_row(state, change, row) do
    Map.update(
      state,
      change.table_name,
      %{change.record_id => row},
      &Map.put(&1, change.record_id, row)
    )
  end

  defp op(op) when op in [:insert, :update, :delete], do: op
  defp op("insert"), do: :insert
  defp op("update"), do: :update
  defp op("delete"), do: :delete

  defp fail!(change, reason) do
    raise Error,
      message:
        "cannot apply change #{change.id} (#{op(change.op)} #{change.table_name} #{change.record_id}): #{reason}"
  end
end
