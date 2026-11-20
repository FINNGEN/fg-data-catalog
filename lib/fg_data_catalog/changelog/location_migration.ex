defmodule FGDataCatalog.Changelog.LocationMigration do
  @moduledoc false

  @legacy_keys ["location", "location_label"]

  def encode_legacy(%{"location" => nil}), do: "[]"

  def encode_legacy(%{"location" => value, "location_label" => label}) do
    Jason.encode!([%{"label" => label, "value" => value}])
  end

  def split_locations(json) do
    case Jason.decode!(json) do
      [] ->
        {%{"location" => nil, "location_label" => nil}, []}

      [%{"value" => value, "label" => label} | rest] ->
        {%{"location" => value, "location_label" => label}, rest}
    end
  end

  def upgrade_in(%{op: :update, old_values: old, new_values: new} = change, row) do
    if Enum.any?(@legacy_keys, &Map.has_key?(new, &1)) do
      # NOTE(Codex-GPT-Sol-6.2 2026-11-19): each side may supply only a label
      # or only a value. Reconstruct the whole entry using the pre-update row.
      before = Map.merge(row, old)
      after_update = Map.merge(before, new)

      %{
        change
        | old_values: upgrade_values(old, before),
          new_values: upgrade_values(new, after_update)
      }
    else
      change
    end
  end

  def upgrade_in(%{op: :insert, new_values: values} = change, _row),
    do: %{change | new_values: upgrade_values(values, values)}

  def upgrade_in(%{op: :delete, old_values: values} = change, _row),
    do: %{change | old_values: upgrade_values(values, values)}

  def downgrade_in(%{op: :update, old_values: old, new_values: new} = change, _row) do
    if Map.has_key?(new, "locations") do
      {old_legacy, _} = split_locations(Map.fetch!(old, "locations"))
      {new_legacy, _} = split_locations(Map.fetch!(new, "locations"))
      keys = Enum.filter(@legacy_keys, &(old_legacy[&1] != new_legacy[&1]))

      %{
        change
        | old_values: downgrade_values(old, Map.take(old_legacy, keys)),
          new_values: downgrade_values(new, Map.take(new_legacy, keys))
      }
    else
      change
    end
  end

  def downgrade_in(%{op: :insert, new_values: values} = change, _row),
    do: %{change | new_values: downgrade_full(values)}

  def downgrade_in(%{op: :delete, old_values: values} = change, _row),
    do: %{change | old_values: downgrade_full(values)}

  defp upgrade_values(values, row) do
    values |> Map.drop(@legacy_keys) |> Map.put("locations", encode_legacy(row))
  end

  defp downgrade_full(values) do
    {legacy, _} = split_locations(Map.fetch!(values, "locations"))
    downgrade_values(values, legacy)
  end

  defp downgrade_values(values, legacy),
    do: values |> Map.delete("locations") |> Map.merge(legacy)
end
