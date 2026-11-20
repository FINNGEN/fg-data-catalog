defmodule FGDataCatalog.Repo.Migrations.AddNotApplicableToDatasetVersions do
  use Ecto.Migration

  alias FGDataCatalog.Changelog.Migration, as: ChangelogMigration

  # NOTE(Claude Opus 5.5 2026-11-18): the fields that do not apply to a version
  # (e.g. no cohort coverage for data that is not about FinnGen individuals),
  # as a list of names: "years_coverage", "cohort_size" (see `DatasetVersion`).
  # Empty for the existing rows, and in the recorded full rows (as JSON text,
  # like every array column).
  def up do
    alter table(:dataset_versions) do
      add :not_applicable, {:array, :string}, null: false, default: []
    end

    ChangelogMigration.add_key("dataset_versions", "not_applicable", "[]")
  end

  # NOTE(Claude Opus 5.5 2026-11-18): the same release added "not_applicable"
  # to the OMOP-mapped values (no column change), which the code before it
  # cannot load: those versions go back to Unknown (NULL), in the table and in
  # the changelog. The data quality answers "na" (Not applicable, also new) are
  # left as they are: the code before reads them as Unknown.
  def down do
    alter table(:dataset_versions) do
      remove :not_applicable
    end

    ChangelogMigration.drop_key("dataset_versions", "not_applicable")

    execute "UPDATE dataset_versions SET omop_integration = NULL WHERE omop_integration = 'not_applicable'"

    ChangelogMigration.rewrite("dataset_versions", fn change ->
      %{
        change
        | old_values: omop_not_applicable_to_nil(change.old_values),
          new_values: omop_not_applicable_to_nil(change.new_values)
      }
    end)
  end

  defp omop_not_applicable_to_nil(%{"omop_integration" => "not_applicable"} = values),
    do: %{values | "omop_integration" => nil}

  defp omop_not_applicable_to_nil(values), do: values
end
