defmodule FGDataCatalog.Repo.Migrations.UseMultipleLocations do
  use Ecto.Migration

  alias FGDataCatalog.Changelog.LocationMigration
  alias FGDataCatalog.Changelog.Migration, as: ChangelogMigration

  def up do
    alter table(:dataset_versions) do
      add :locations, {:array, :map}, null: false, default: []
    end

    flush()

    for [id, value, label] <-
          repo().query!("SELECT id, location, location_label FROM dataset_versions").rows do
      locations =
        LocationMigration.encode_legacy(%{"location" => value, "location_label" => label})

      repo().query!("UPDATE dataset_versions SET locations = ? WHERE id = ?", [locations, id])
    end

    alter table(:dataset_versions) do
      remove :location
      remove :location_label
    end

    ChangelogMigration.rewrite("dataset_versions", &LocationMigration.upgrade_in/2)
  end

  def down do
    alter table(:dataset_versions) do
      add :location, :string
      add :location_label, :string
    end

    # NOTE(Codex-GPT-Sol-6.2 2026-11-19): keep each rollback's extra entries
    # for manual recovery. Reapplying up uses the legacy values as they stand.
    create_if_not_exists table(:locations_rollback) do
      add :version_id, :integer, null: false
      add :locations, :text, null: false
      add :rolled_back_at, :utc_datetime, null: false
    end

    flush()
    rolled_back_at = DateTime.utc_now(:second) |> DateTime.to_iso8601()

    for [id, locations] <- repo().query!("SELECT id, locations FROM dataset_versions").rows do
      {%{"location" => value, "location_label" => label}, extra} =
        LocationMigration.split_locations(locations)

      repo().query!("UPDATE dataset_versions SET location = ?, location_label = ? WHERE id = ?", [
        value,
        label,
        id
      ])

      if extra != [] do
        repo().query!(
          "INSERT INTO locations_rollback (version_id, locations, rolled_back_at) VALUES (?, ?, ?)",
          [id, Jason.encode!(extra), rolled_back_at]
        )
      end
    end

    alter table(:dataset_versions) do
      remove :locations
    end

    ChangelogMigration.rewrite("dataset_versions", &LocationMigration.downgrade_in/2)
  end
end
