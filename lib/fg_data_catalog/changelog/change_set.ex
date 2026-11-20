defmodule FGDataCatalog.Changelog.ChangeSet do
  @moduledoc """
  One user action in the changelog, e.g. "create dataset" or "edit version".
  Groups the row changes it made, see `FGDataCatalog.Changelog.Change`.
  """
  use Ecto.Schema

  schema "change_sets" do
    # NOTE(Claude Opus 5.5 2026-11-17): the signed-in user's email, `nil` for
    # scripts. (The dev database also holds "session:<token>" actors and a
    # "baseline" change set without one, from before sign-in.)
    field :actor, :string
    field :action, :string

    has_many :changes, FGDataCatalog.Changelog.Change, preload_order: [asc: :id]

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
