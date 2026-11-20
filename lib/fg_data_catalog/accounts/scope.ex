defmodule FGDataCatalog.Accounts.Scope do
  @moduledoc """
  Who is making a request.

  NOTE(Claude 2026-11-16): `nil` for a visitor who has not signed in: they see
  the Published versions only. Every signed-in user is an editor; there is no
  admin any more. What an editor may do with a version depends on its state
  and on whether they are its owning editor: see
  `FGDataCatalog.Catalog.can?/3`.
  """
  alias FGDataCatalog.Accounts.User

  defstruct user: nil

  @doc "The scope of `user`, or `nil` without one."
  def for_user(%User{} = user), do: %__MODULE__{user: user}
  def for_user(nil), do: nil

  @doc "Whether the scope is an editor: any signed-in user."
  def editor?(%__MODULE__{user: %User{}}), do: true
  def editor?(_scope), do: false

  @doc """
  Who made a change, as recorded in the changelog (`change_sets.actor`): the
  user's email.
  """
  def actor(%__MODULE__{user: %User{email: email}}), do: email
  def actor(_scope), do: nil

  @doc """
  The id of the scope's user, or `nil`: a version's owning editor
  (`dataset_versions.owning_editor_id`) and the owner of an autosaved new
  dataset (`dataset_drafts.user_id`).
  """
  # NOTE(Claude 2026-11-12): an id rather than the email, which may change.
  def user_id(%__MODULE__{user: %User{id: id}}), do: id
  def user_id(_scope), do: nil
end
