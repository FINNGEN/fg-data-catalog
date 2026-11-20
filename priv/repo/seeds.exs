# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# NOTE(Claude Opus 5.5 2026-11-20): loads the catalog from `seeds/catalog.json`,
# a fictional catalog (datasets and versions only, no users: `owning_editor_id`
# is null). The whole catalog is one change set
# ("seed catalog"), so the changelog starts with only its inserts. Runs only on
# a database without datasets.
#
# The JSON holds each row's columns, with array, embed and map columns as JSON
# values (they are JSON text in SQLite). To refresh it from a database, export
# `FGDataCatalog.Changelog.snapshot/0` the same way.

import Ecto.Query

alias FGDataCatalog.Catalog.{Dataset, DatasetVersion}
alias FGDataCatalog.Changelog
alias FGDataCatalog.Repo

path = Path.join(__DIR__, "seeds/catalog.json")

# NOTE(Claude Opus 5.5 2026-11-17): back to raw column values (JSON text for
# arrays, embeds and maps), then loaded as the schema's struct: ids, timestamps
# and every column are kept as they were.
load_row = fn schema, row ->
  row =
    Map.new(row, fn
      {column, value} when is_list(value) or is_map(value) -> {column, Jason.encode!(value)}
      pair -> pair
    end)

  Repo.load(schema, row)
end

if Repo.exists?(from(d in Dataset)) do
  IO.puts("The database already has datasets: not seeding.")
else
  catalog = path |> File.read!() |> Jason.decode!()

  {:ok, counts} =
    Changelog.transact("seed catalog", "seeds", fn set ->
      counts =
        for {schema, table} <- [{Dataset, "datasets"}, {DatasetVersion, "dataset_versions"}] do
          for row <- Map.fetch!(catalog, table) do
            {:ok, _record} =
              Changelog.insert(set, Ecto.Changeset.change(load_row.(schema, row)))
          end

          {table, length(Map.fetch!(catalog, table))}
        end

      {:ok, counts}
    end)

  for {table, count} <- counts, do: IO.puts("Seeded #{count} #{table}")
end
