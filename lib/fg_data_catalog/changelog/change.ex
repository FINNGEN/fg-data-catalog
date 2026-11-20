defmodule FGDataCatalog.Changelog.Change do
  @moduledoc """
  One row inserted, updated or deleted by a change set.

  Values are raw column values, as stored in SQLite (see `FGDataCatalog.Changelog`):

    * `:insert`: `new_values` holds the whole new row, `old_values` is `nil`.
    * `:update`: `old_values` and `new_values` hold the changed columns only.
    * `:delete`: `old_values` holds the whole deleted row, `new_values` is `nil`.
  """
  use Ecto.Schema

  schema "changes" do
    field :table_name, :string
    field :record_id, :integer
    field :op, Ecto.Enum, values: [:insert, :update, :delete]
    field :old_values, :map
    field :new_values, :map

    belongs_to :change_set, FGDataCatalog.Changelog.ChangeSet
  end
end
