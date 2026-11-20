defmodule FGDataCatalog.Repo.Migrations.AddLocationToDatasetVersions do
  use Ecto.Migration

  alias FGDataCatalog.Changelog.Migration, as: ChangelogMigration

  # NOTE(Claude Opus 5.5 2026-11-17): where to find the data: a web link or a
  # Unix path (see `DatasetVersion`), optional, and the short name it is shown
  # under in the catalog (e.g. "Web page"), optional. The recorded full rows
  # get the new columns, as `nil`.
  def up do
    alter table(:dataset_versions) do
      add :location, :string
      add :location_label, :string
    end

    ChangelogMigration.add_key("dataset_versions", "location", nil)
    ChangelogMigration.add_key("dataset_versions", "location_label", nil)
  end

  def down do
    alter table(:dataset_versions) do
      remove :location_label
      remove :location
    end

    ChangelogMigration.drop_key("dataset_versions", "location_label")
    ChangelogMigration.drop_key("dataset_versions", "location")
  end
end
