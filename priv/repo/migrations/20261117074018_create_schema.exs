defmodule FGDataCatalog.Repo.Migrations.CreateSchema do
  use Ecto.Migration

  # NOTE(Claude Opus 5.5 2026-11-17): the whole schema, replacing the 18
  # migrations written during development (before any production database
  # existed). Later schema changes go in migrations of their own, which also
  # rewrite the recorded changelog values (see `FGDataCatalog.Changelog.Migration`).
  #
  # SQLite has no array or map types: ecto_sqlite3 stores `{:array, _}` and
  # `:map` columns as JSON text.
  def change do
    # NOTE(Claude Opus 5.5 2026-11-17): the people who sign in with Google, and
    # their session tokens. Not catalog data, so not in the changelog. There are
    # no passwords: Google vouches for the email. `google_sub` is Google's stable
    # account id; the email may change. Tokens are stored hashed (SHA-256), the
    # raw token living only in the session cookie.
    create table(:users) do
      add :email, :string, null: false, collate: :nocase
      add :name, :string
      add :google_sub, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:google_sub])

    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      add :context, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token_hash])

    create table(:datasets) do
      add :name, :string, null: false
      add :description, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:datasets, [:name])

    # NOTE(Claude Opus 5.5 2026-11-17): `owning_editor_id` has no `on_delete`
    # action: a database cascade on a tracked table would not be logged (see
    # `FGDataCatalog.Changelog`). Nothing deletes users today.
    create table(:dataset_versions) do
      add :dataset_id, references(:datasets, on_delete: :delete_all), null: false
      add :version, :string, null: false
      add :release_date, :date, null: false
      add :state, :string, null: false, default: "draft"
      add :owning_editor_id, references(:users, on_delete: :nothing)
      add :archived_at, :utc_datetime
      # NOTE(Claude Opus 5.5 2026-11-17): the dataset name and description a
      # Draft proposes, applied to its dataset on publish.
      add :dataset_name, :string
      add :dataset_description, :string
      add :tags, {:array, :string}, null: false
      add :environments, {:array, :string}, null: false
      add :access_type, :string
      add :formats, {:array, :string}, null: false
      add :modalities, {:array, :string}, null: false, default: []
      add :data_quality, :map, null: false, default: %{}
      add :omop_integration, :string
      # NOTE(Claude Opus 5.5 2026-11-17): years, both included.
      add :coverage_start, :integer
      add :coverage_end, :integer
      add :cohort_size, :integer
      add :lead, :string
      # NOTE(Claude 2026-11-04): default [] because Ecto leaves an embed out of
      # an INSERT when it has no entries.
      add :doc_links, {:array, :map}, null: false, default: []
      add :data_dictionary, {:array, :map}, null: false, default: []
      add :yearly_counts, {:array, :map}, null: false, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:dataset_versions, [:dataset_id, :version])
    create index(:dataset_versions, [:state])
    create index(:dataset_versions, [:owning_editor_id])

    # NOTE(Claude 2026-11-03): an unsaved "new dataset" row, autosaved as it is
    # edited, one per user. `params` are the raw, unvalidated form params, so a
    # half-filled row can be stored even though `dataset_versions` requires
    # some columns. Not catalog data: deleted with its user.
    create table(:dataset_drafts) do
      add :user_id, references(:users, on_delete: :delete_all)
      add :params, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:dataset_drafts, [:user_id])

    # NOTE(Claude 2026-11-03): the changelog of the catalog tables (`datasets`,
    # `dataset_versions`), see `FGDataCatalog.Changelog`. Each user action is one
    # `change_sets` row; each row it inserted, updated or deleted is one
    # `changes` row holding the raw column values before and after: the whole
    # row for an insert (new) or a delete (old), only the changed columns for an
    # update (both).
    create table(:change_sets) do
      add :actor, :string
      add :action, :string, null: false
      add :inserted_at, :utc_datetime, null: false
    end

    create table(:changes) do
      add :change_set_id, references(:change_sets, on_delete: :restrict), null: false
      add :table_name, :string, null: false
      add :record_id, :integer, null: false
      add :op, :string, null: false
      add :old_values, :map
      add :new_values, :map
    end

    create index(:changes, [:change_set_id])
    create index(:changes, [:table_name, :record_id])
  end
end
