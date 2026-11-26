defmodule FGDataCatalog.Catalog do
  @moduledoc """
  The catalog of FinnGen datasets and their versions.

  NOTE(Claude 2026-11-16): each version is in one state, Draft, Published or
  Archived, and may have an owning editor. Who may do what with it is
  `can?/3`, checked by every function below that changes a version, against
  the version as it is in the database when the change is saved.
  """
  import Ecto.Query, warn: false

  alias FGDataCatalog.Repo
  alias FGDataCatalog.Catalog.{Dataset, DatasetDraft, DatasetVersion}
  alias FGDataCatalog.Changelog
  alias FGDataCatalog.Accounts.Scope

  @actions [:read, :write, :publish, :delete, :unpublish, :archive, :unarchive]

  @doc """
  Whether `scope` may do `action` with `version`: one of #{inspect(@actions)}.

  | State \\ Actor | Logged out | Non-owning editor | Owning editor |
  |---|---|---|---|
  | Published | read | read, write, unpublish, archive | read, write, unpublish, archive |
  | Draft | – | read, write, publish, delete | read, write, publish, delete |
  | Archived | – | read, unarchive | read, unarchive |

  Every signed-in user is an editor (`FGDataCatalog.Accounts.Scope.editor?/1`).
  The owning editor is the version's `owning_editor_id`; a version without
  one has no owning editor.
  """
  # NOTE(Claude 2026-11-16): the one rule table (see DONE.md, "Version states
  # and editors"), used by the context functions and the templates alike.
  def can?(scope, action, %DatasetVersion{state: state} = version) when action in @actions do
    editor? = Scope.editor?(scope)
    owner? = editor? and owning_editor?(scope, version)
    allowed?(action, state, editor?, owner?)
  end

  defp owning_editor?(scope, %DatasetVersion{owning_editor_id: id}),
    do: id != nil and id == Scope.user_id(scope)

  # NOTE(Claude-Opus-5.5 2026-11-26): a Draft is every editor's, whoever owns
  # it (the owner is shown, not enforced). Drafts are deleted, not archived.
  defp allowed?(action, :draft, editor?, _owner?),
    do: editor? and action in [:read, :write, :publish, :delete]

  defp allowed?(:read, :published, _editor?, _owner?), do: true
  defp allowed?(:read, _state, editor?, _owner?), do: editor?
  defp allowed?(:write, :published, editor?, _owner?), do: editor?
  defp allowed?(:unpublish, :published, editor?, _owner?), do: editor?
  defp allowed?(:archive, :published, editor?, _owner?), do: editor?
  defp allowed?(:unarchive, :archived, editor?, _owner?), do: editor?
  defp allowed?(_action, _state, _editor?, _owner?), do: false

  @doc """
  The catalog as `scope` sees it: the datasets with at least one version it
  may see, each with those versions in `versions`, newest first (by release
  date, as version strings do not sort reliably: "R9" > "R14"). The head is
  the dataset's current version, the tail its previous versions.

  Everyone sees the Published versions; editors (signed-in users) also every
  Draft, sorted among them by release date, so that a newer Draft is its
  dataset's first version for every editor. Archived versions are left out
  (see `list_archived_versions/0`); a dataset whose versions are all archived
  is not listed.

  Datasets are ordered by the release date of their first (latest) version,
  newest first; datasets released the same day by name.
  """
  # NOTE(Claude 2026-11-09): ordered by release date, not by name. The query
  # orders by name and `Enum.sort_by/3` is stable, so name breaks the ties.
  # NOTE(Claude 2026-11-16): editors see the owning editor of each version
  # (the Draft badge names them).
  def list_datasets(scope) do
    versions_query =
      from v in DatasetVersion,
        where: ^visible_versions(scope),
        order_by: [desc: v.release_date, desc: v.id]

    versions_query =
      if Scope.editor?(scope), do: preload(versions_query, :owning_editor), else: versions_query

    from(d in Dataset, order_by: d.name, preload: [versions: ^versions_query])
    |> Repo.all()
    |> Enum.reject(&(&1.versions == []))
    |> Enum.sort_by(&hd(&1.versions).release_date, {:desc, Date})
  end

  @doc "The catalog as a visitor who has not signed in sees it."
  def list_published_datasets, do: list_datasets(nil)

  # NOTE(Claude 2026-11-16): the versions of the catalog: `can?(scope, :read,
  # version)`, but for the archived ones, as a query.
  defp visible_versions(scope) do
    if Scope.editor?(scope),
      do: dynamic([v], v.state in [:published, :draft]),
      else: dynamic([v], v.state == :published)
  end

  @doc """
  Lists the archived versions, most recently archived first, each with its
  `dataset`. The page that lists them is for editors.
  """
  def list_archived_versions do
    from(v in DatasetVersion,
      where: v.state == :archived,
      order_by: [desc_nulls_last: v.archived_at, desc: v.id],
      preload: :dataset
    )
    |> Repo.all()
  end

  # NOTE(Claude 2026-11-16): the state transitions below take the `scope` of
  # who is asking (see `FGDataCatalog.Accounts.Scope`), checked with `can?/3`
  # against the version as it is in the database, whatever the page showed,
  # and record its user as the changelog actor. Whoever moves a version into
  # Draft (unpublish, unarchive) becomes its owning editor, in the same change
  # set; publish and archive leave the owner as it is.

  @doc """
  Archives `version`: it leaves the catalog but stays in the database. Returns
  `{:error, :unauthorized}` if `scope` may not (see `can?/3`).
  """
  def archive_version(scope, %DatasetVersion{} = version) do
    transition(scope, version, :archive, "archive version", fn _version ->
      %{state: :archived, archived_at: DateTime.utc_now(:second)}
    end)
  end

  @doc """
  Puts an archived `version` back in the catalog as a Draft owned by the
  `scope`'s user. Returns `{:error, :unauthorized}` if `scope` may not.
  """
  def unarchive_version(scope, %DatasetVersion{} = version) do
    transition(scope, version, :unarchive, "unarchive version", fn _version ->
      %{state: :draft, archived_at: nil, owning_editor_id: Scope.user_id(scope)}
    end)
  end

  @doc """
  Turns a Published `version` back into a Draft owned by the `scope`'s user.
  Returns `{:error, :unauthorized}` if `scope` may not.
  """
  def unpublish_dataset_version(scope, %DatasetVersion{} = version) do
    transition(scope, version, :unpublish, "unpublish version", fn _version ->
      %{state: :draft, owning_editor_id: Scope.user_id(scope)}
    end)
  end

  @doc """
  Deletes a draft `version` for good, and its dataset if it has no other
  version (archived ones included). Recorded in the changelog, so it can be
  reverted. Returns `{:ok, version}`, or `{:error, :unauthorized}` if `scope`
  may not (see `can?/3`).
  """
  def delete_draft_version(scope, %DatasetVersion{} = version) do
    Changelog.transact("delete draft", Scope.actor(scope), fn set ->
      with {:ok, current} <- authorize(scope, :delete, version),
           {:ok, deleted} <- Changelog.delete(set, current) do
        others = from v in DatasetVersion, where: v.dataset_id == ^current.dataset_id

        if Repo.exists?(others) do
          {:ok, deleted}
        else
          with {:ok, _dataset} <-
                 Changelog.delete(set, Repo.get!(Dataset, current.dataset_id)),
               do: {:ok, deleted}
        end
      end
    end)
  end

  @doc """
  Publishes a Draft `version`, making it visible to everyone. The dataset name
  and description it proposes (see `update_dataset_row/5`) are applied to its
  dataset in the same change set.

  Returns `{:ok, version}`, `{:error, :unauthorized}` if `scope` may not (see
  `can?/3`), or `{:error, changeset}` with the dataset changeset
  if the proposed name is no longer valid (e.g. another dataset took it).
  """
  def publish_dataset_version(scope, %DatasetVersion{} = version) do
    Changelog.transact("publish version", Scope.actor(scope), fn set ->
      with {:ok, current} <- authorize(scope, :publish, version),
           {:ok, _dataset} <- apply_proposed_dataset(set, current) do
        Changelog.update(
          set,
          Ecto.Changeset.change(current,
            state: :published,
            dataset_name: nil,
            dataset_description: nil
          )
        )
      end
    end)
  end

  defp transition(scope, version, action, name, changes) do
    Changelog.transact(name, Scope.actor(scope), fn set ->
      with {:ok, current} <- authorize(scope, action, version) do
        Changelog.update(set, Ecto.Changeset.change(current, changes.(current)))
      end
    end)
  end

  # NOTE(Claude 2026-11-16): `version` as it is in the database now, if
  # `scope` may do `action` with it. Called inside the change set's
  # transaction, so that the check and the change see the same row.
  defp authorize(scope, action, %DatasetVersion{id: id}) do
    case Repo.get(DatasetVersion, id) do
      %DatasetVersion{} = current ->
        if can?(scope, action, current), do: {:ok, current}, else: {:error, :unauthorized}

      nil ->
        {:error, :unauthorized}
    end
  end

  defp apply_proposed_dataset(_set, %DatasetVersion{dataset_name: nil, dataset_description: nil}),
    do: {:ok, nil}

  defp apply_proposed_dataset(set, %DatasetVersion{} = version) do
    dataset = Repo.get!(Dataset, version.dataset_id)
    proposed = proposed_dataset(dataset, version)
    attrs = %{name: proposed.name, description: proposed.description}

    Changelog.update(set, dataset |> Dataset.changeset(attrs) |> validate_name_free(dataset.id))
  end

  @doc """
  `dataset` as `version` shows it: with the name and description the version
  proposes, if it is a Draft that proposes any (see `update_dataset_row/5`).
  """
  def proposed_dataset(%Dataset{} = dataset, %DatasetVersion{} = version) do
    description =
      case version.dataset_description do
        nil -> dataset.description
        "" -> nil
        description -> description
      end

    %{dataset | name: version.dataset_name || dataset.name, description: description}
  end

  # NOTE(Claude 2026-11-16): checked before saving, rather than leaving it to
  # the unique index, for a name proposed by a Draft (not written to
  # `datasets` until publish).
  defp validate_name_free(changeset, dataset_id) do
    Ecto.Changeset.validate_change(changeset, :name, fn :name, name ->
      if Repo.exists?(from d in Dataset, where: d.name == ^name and d.id != ^dataset_id),
        do: [name: "has already been taken"],
        else: []
    end)
  end

  @doc """
  Reverts change set `set_id`, or a run of live edits given as the list of its
  change set ids (see `FGDataCatalog.Changelog.revert/2`). Any editor may;
  others get `{:error, :unauthorized}`.
  """
  # NOTE(Claude 2026-11-16): a revert writes the recorded columns back (state,
  # owner, fields included), so it can undo any transition or a draft owner's
  # edits. Accepted: the changelog records who did it.
  def revert_change_set(scope, set_id) do
    if Scope.editor?(scope),
      do: Changelog.revert(set_id, Scope.actor(scope)),
      else: {:error, :unauthorized}
  end

  # NOTE(Claude 2026-11-04): `list_tags/0`, `list_modalities/0` and
  # `list_formats/0` feed the autocomplete of the dataset forms.
  @doc """
  Lists every tag used by a dataset version that is not archived, sorted and
  without duplicates.
  """
  def list_tags, do: distinct_values(:tags)

  @doc """
  Like `list_tags/0`, for the modalities (what the data is).
  """
  def list_modalities, do: distinct_values(:modalities)

  @doc """
  Like `list_tags/0`, for the formats (how the data is stored or delivered).
  """
  def list_formats, do: distinct_values(:formats)

  @doc """
  Like `list_tags/0`, for the environments (where the data can be used).
  """
  # NOTE(Claude-Opus-5.5 2026-11-26): for the Environments field, on the edit
  # page and in the catalog's quick edit.
  def list_environments, do: distinct_values(:environments)

  # NOTE(Claude 2026-11-06): archived versions no longer feed the suggestions.
  defp distinct_values(field) do
    from(v in DatasetVersion, where: v.state != :archived, select: field(v, ^field))
    |> Repo.all()
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort_by(&String.downcase/1)
  end

  # NOTE(Claude 2026-11-03): every write below goes through
  # `FGDataCatalog.Changelog`, which records it in the changelog. `opts[:actor]`
  # names who made the change.

  @doc """
  Returns a changeset for a new dataset together with its first version, for
  use in forms. Takes the same `opts` as `create_dataset_version/3`.
  """
  def change_new_dataset(%Dataset{} = dataset, attrs \\ %{}, opts \\ []) do
    dataset
    |> Dataset.changeset(attrs)
    |> Ecto.Changeset.cast_assoc(:versions,
      required: true,
      with: &DatasetVersion.changeset(new_version(&1, opts), &2)
    )
    |> Ecto.Changeset.validate_length(:versions, is: 1)
  end

  @doc "Creates a dataset and its first version in one transaction."
  def create_dataset_with_version(attrs, opts \\ []) do
    Changelog.transact("create dataset", opts[:actor], fn set ->
      Changelog.insert(set, change_new_dataset(%Dataset{}, attrs, opts))
    end)
  end

  def create_dataset(attrs, opts \\ []) do
    Changelog.transact("create dataset", opts[:actor], fn set ->
      Changelog.insert(set, Dataset.changeset(%Dataset{}, attrs))
    end)
  end

  @doc """
  Creates a version of `dataset`.

  `opts` sets the fields that must not come from user input: `:state`
  (default `:draft`) and `:owning_editor_id` (a user id); and `:actor`.
  """
  def create_dataset_version(%Dataset{} = dataset, attrs, opts \\ []) do
    changeset =
      %DatasetVersion{dataset_id: dataset.id}
      |> new_version(opts)
      |> DatasetVersion.changeset(attrs)

    Changelog.transact("create version", opts[:actor], &Changelog.insert(&1, changeset))
  end

  @doc """
  Tells why a new dataset may not be named `name`: which dataset holds the
  name, and whether `scope` sees it (see `list_datasets/1`). Returns `nil` if
  the name is free.

    * `{:listed, dataset}`: in the catalog as `scope` sees it.
    * `{:archived, dataset}`: all its versions are archived.
    * `{:unpublished, dataset}`: its versions are Drafts `scope` does not
      see, or it has none.
  """
  # NOTE(Claude 2026-11-06): the unique name constraint alone said "has already
  # been taken" even when no dataset of that name was visible.
  # NOTE(Claude 2026-11-16): takes the scope (signed in or not), no longer
  # `admin:` / `user_id:` options.
  def dataset_name_holder(name, scope) when is_binary(name) do
    with name when name != "" <- String.trim(name),
         %Dataset{} = dataset <- Repo.get_by(Dataset, name: name) do
      versions = from(v in DatasetVersion, where: v.dataset_id == ^dataset.id)
      active = where(versions, [v], v.state != :archived)

      cond do
        Repo.exists?(where(active, ^visible_versions(scope))) -> {:listed, dataset}
        Repo.exists?(active) -> {:unpublished, dataset}
        Repo.exists?(versions) -> {:archived, dataset}
        true -> {:unpublished, dataset}
      end
    else
      _ -> nil
    end
  end

  def dataset_name_holder(_name, _scope), do: nil

  @doc """
  Returns the dataset `id` and its latest version (or `nil`), to add a new
  version to it, if `scope` may: any editor, to any dataset, even one whose
  versions are all archived. The latest version is the newest by release date
  that is not archived, or else the newest archived one.
  """
  # NOTE(Claude 2026-11-06): for the "Add version" page, which is prefilled from
  # the latest version (see `new_version_params/1`).
  def get_dataset_for_new_version(id, scope) do
    latest =
      from v in DatasetVersion,
        where: v.dataset_id == ^id,
        order_by: [
          asc: fragment("? = 'archived'", v.state),
          desc: v.release_date,
          desc: v.id
        ],
        limit: 1

    with true <- Scope.editor?(scope),
         %Dataset{} = dataset <- Repo.get(Dataset, id) do
      {dataset, Repo.one(latest)}
    else
      _ -> nil
    end
  end

  @doc """
  The form params of a new version prefilled from `version`: everything but
  what changes with each release (version, release date, data dictionary,
  yearly counts, coverage period and individuals covered) and what the
  application sets (state, owning editor, proposed dataset name and
  description, archiving).
  """
  def new_version_params(nil), do: %{}

  def new_version_params(%DatasetVersion{} = version) do
    lists = ~w(tags environments formats modalities)a
    # NOTE(Claude 2026-11-10): the coverage period and the individuals covered
    # (`cohort_size`) are no longer copied: they change with each release.
    scalars = ~w(access_type omop_integration lead)a

    params =
      Map.new(lists ++ scalars, fn field -> {Atom.to_string(field), Map.get(version, field)} end)

    doc_links =
      version.doc_links
      |> Enum.with_index()
      |> Map.new(fn {link, index} ->
        {Integer.to_string(index),
         Map.take(link, [:kind, :label, :url, :text]) |> stringify_keys()}
      end)

    params
    # NOTE(Claude 2026-11-16): the answers to the data quality criteria too.
    |> Map.put("data_quality", version.data_quality)
    # NOTE(Claude Opus 5.5 2026-11-18): and the fields that do not apply,
    # which describe the dataset more than the release.
    |> Map.put("not_applicable", version.not_applicable)
    |> Map.put("doc_links", doc_links)
  end

  defp stringify_keys(map), do: Map.new(map, fn {k, v} -> {Atom.to_string(k), v} end)

  @doc "Returns version `id` with its dataset and owning editor, or `nil`."
  def get_dataset_version(id) do
    DatasetVersion |> Repo.get(id) |> Repo.preload([:dataset, :owning_editor])
  end

  @doc "Returns a changeset for editing a dataset's own fields (name, description)."
  def change_dataset(%Dataset{} = dataset, attrs \\ %{}), do: Dataset.changeset(dataset, attrs)

  @doc "Returns a changeset for editing a version."
  def change_dataset_version(%DatasetVersion{} = version, attrs \\ %{}) do
    DatasetVersion.changeset(version, attrs)
  end

  @doc """
  Edits a catalog row: a version and, optionally, its dataset's own fields
  (name, description), as one change set. The changes apply at once, without
  approval.

  `opts[:scope]` is who edits: they must be allowed to write the version as
  it is in the database (see `can?/3`); otherwise nothing is saved and
  `{:error, :unauthorized}` is returned. Its user is the changelog actor.

  The dataset's fields edited through a Draft of a dataset that has a
  Published version are not written to the dataset, which the Published
  versions show, but stored on the Draft (`dataset_name`,
  `dataset_description`) until it is published (see
  `publish_dataset_version/2`). Edited through any other version, they are
  written to the dataset (and clear what the version proposed, if anything).
  `dataset_attrs` are then relative to `proposed_dataset/2`.

  Returns `{:ok, %{dataset: dataset, version: version}}` (the dataset as
  stored), or `{:error, changeset}` with the failing dataset or version
  changeset (nothing is saved).
  """
  def update_dataset_row(
        %Dataset{} = dataset,
        dataset_attrs,
        %DatasetVersion{} = version,
        version_attrs,
        opts \\ []
      ) do
    scope = opts[:scope]

    Changelog.transact("edit row", Scope.actor(scope), fn set ->
      with {:ok, current} <- authorize(scope, :write, version),
           {:ok, dataset, proposed} <- write_dataset(set, dataset, dataset_attrs, current),
           version_changeset =
             version
             |> change_dataset_version(version_attrs)
             |> force_changes(proposed),
           {:ok, version} <- Changelog.update(set, version_changeset) do
        {:ok, %{dataset: dataset, version: version}}
      end
    end)
  end

  # NOTE(Claude 2026-11-16): returns the dataset as stored and the changes of
  # the version's proposed name and description.
  defp write_dataset(_set, dataset, attrs, _version) when attrs == %{}, do: {:ok, dataset, %{}}

  defp write_dataset(set, dataset, attrs, version) do
    if version.state == :draft and published_version?(dataset.id) do
      changeset =
        dataset
        |> proposed_dataset(version)
        |> Dataset.changeset(attrs)
        |> validate_name_free(dataset.id)

      if changeset.valid? do
        %{name: name, description: description} = Ecto.Changeset.apply_changes(changeset)

        {:ok, dataset,
         %{
           dataset_name: if(name != dataset.name, do: name),
           dataset_description: if(description != dataset.description, do: description || "")
         }}
      else
        {:error, %{changeset | action: :update}}
      end
    else
      with {:ok, dataset} <- Changelog.update(set, change_dataset(dataset, attrs)) do
        {:ok, dataset, %{dataset_name: nil, dataset_description: nil}}
      end
    end
  end

  # NOTE(Claude 2026-11-16): forced, as `version` may be older than the row:
  # `Changelog.update/2` logs only the columns that really change.
  defp force_changes(changeset, changes) do
    Enum.reduce(changes, changeset, fn {field, value}, changeset ->
      Ecto.Changeset.force_change(changeset, field, value)
    end)
  end

  defp published_version?(dataset_id) do
    Repo.exists?(
      from v in DatasetVersion, where: v.dataset_id == ^dataset_id and v.state == :published
    )
  end

  # NOTE(Claude 2026-11-12): the drafts below are keyed by user id, no longer
  # by email.
  @doc "Returns the params of user `user_id`'s unsaved new dataset, or `nil`."
  def get_dataset_draft_params(user_id) when is_integer(user_id) do
    from(d in DatasetDraft, where: d.user_id == ^user_id, select: d.params)
    |> Repo.one()
  end

  def get_dataset_draft_params(nil), do: nil

  @doc """
  Stores `params` as user `user_id`'s unsaved new dataset, replacing any
  previous draft. The params are not validated: a draft may be incomplete.
  """
  def save_dataset_draft(user_id, params) when is_integer(user_id) and is_map(params) do
    now = DateTime.utc_now(:second)

    Repo.insert(
      %DatasetDraft{user_id: user_id, params: params, inserted_at: now, updated_at: now},
      on_conflict: [set: [params: params, updated_at: now]],
      conflict_target: :user_id
    )
  end

  @doc "Deletes user `user_id`'s unsaved new dataset, if any."
  def delete_dataset_draft(user_id) when is_integer(user_id) do
    from(d in DatasetDraft, where: d.user_id == ^user_id) |> Repo.delete_all()
    :ok
  end

  def delete_dataset_draft(nil), do: :ok

  defp new_version(%DatasetVersion{} = version, opts) do
    %{
      version
      | state: Keyword.get(opts, :state, :draft),
        owning_editor_id: Keyword.get(opts, :owning_editor_id)
    }
  end
end
