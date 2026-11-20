defmodule FGDataCatalogWeb.DatasetLive.VersionParams do
  @moduledoc """
  Turns the form params of a version into the attributes its changeset casts.
  Shared by the dataset form pages (`FGDataCatalogWeb.DatasetLive.Form`) and the
  catalog's quick edit (`FGDataCatalogWeb.DatasetLive.Index`).
  """
  # NOTE(Claude 2026-11-10): moved out of `DatasetLive.Form`, for the quick edit.

  # NOTE(Claude 2026-11-03): these set-valued fields are typed as comma-separated text.
  @comma_separated_fields ~w(tags environments formats modalities)

  @doc """
  Splits the comma-separated list fields of a version's params.

      iex> split_lists(%{"tags" => "A, B", "version" => "R1"})
      %{"tags" => ["A", " B"], "version" => "R1"}
  """
  def split_lists(version) when is_map(version) do
    Enum.reduce(@comma_separated_fields, version, fn field, acc ->
      case acc do
        %{^field => value} when is_binary(value) -> %{acc | field => String.split(value, ",")}
        _ -> acc
      end
    end)
  end

  def split_lists(version), do: version
end
