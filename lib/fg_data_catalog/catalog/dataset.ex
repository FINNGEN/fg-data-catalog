defmodule FGDataCatalog.Catalog.Dataset do
  @moduledoc """
  A dataset's stable identity. Everything that can change between releases
  lives on `FGDataCatalog.Catalog.DatasetVersion`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias FGDataCatalog.Catalog.DatasetVersion

  schema "datasets" do
    field :name, :string
    # NOTE(Claude 2026-11-09): what the dataset is, in a few words. Optional.
    field :description, :string

    has_many :versions, DatasetVersion

    timestamps(type: :utc_datetime)
  end

  # NOTE(Claude 2026-11-09): "a few words": long enough for a short phrase,
  # short enough to stay one or two lines in the catalog.
  @description_max_length 120

  def description_max_length, do: @description_max_length

  def changeset(dataset, attrs) do
    dataset
    |> cast(attrs, [:name, :description])
    # NOTE(Claude 2026-11-16): a cleared name is a `nil` change too.
    |> update_change(:name, &(&1 && String.trim(&1)))
    # NOTE(Claude 2026-11-09): a cleared description is a `nil` change.
    |> update_change(:description, &(&1 && String.trim(&1)))
    |> validate_required([:name])
    |> validate_length(:description, max: @description_max_length)
    |> unique_constraint(:name)
  end
end
