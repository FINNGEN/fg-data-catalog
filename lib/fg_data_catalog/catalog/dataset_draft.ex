defmodule FGDataCatalog.Catalog.DatasetDraft do
  @moduledoc """
  The unsaved "new dataset" row of one user, autosaved as it is edited so that
  it can be restored after the page is closed.

  `params` are the raw form params, stored unvalidated: a draft may be
  incomplete. They are validated by `FGDataCatalog.Catalog.change_new_dataset/3`
  when the draft is restored or saved.
  """
  use Ecto.Schema

  schema "dataset_drafts" do
    # NOTE(Claude 2026-11-12): the signed-in user whose draft it is.
    belongs_to :user, FGDataCatalog.Accounts.User
    field :params, :map, default: %{}

    timestamps(type: :utc_datetime)
  end
end
