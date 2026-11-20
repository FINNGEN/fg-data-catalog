defmodule FGDataCatalog.Catalog.YearCount do
  @moduledoc "Number of data points available for a given year."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :year, :integer
    field :count, :integer
  end

  def changeset(year_count, attrs) do
    year_count
    |> cast(attrs, [:year, :count])
    |> validate_required([:year, :count])
    |> validate_number(:count, greater_than_or_equal_to: 0)
  end
end
