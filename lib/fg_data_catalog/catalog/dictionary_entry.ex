defmodule FGDataCatalog.Catalog.DictionaryEntry do
  @moduledoc "One column of a dataset version's data dictionary."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :col_name, :string
    field :details, :string
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:col_name, :details])
    |> validate_required([:col_name])
  end
end
