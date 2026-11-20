defmodule Mix.Tasks.Changelog.Verify do
  @shortdoc "Checks that the changelog replays on the current tables"

  @moduledoc """
  Checks that the changelog still fits the current tables: each recorded
  change, and a replay forward and backward (see
  `FGDataCatalog.Changelog.Verify`). Run it after each migration that changes
  a column of `datasets` or `dataset_versions` (see
  `FGDataCatalog.Changelog.Migration`), on the dev database and on a copy of
  the production one.

      mix changelog.verify
      mix changelog.verify --database /tmp/prod-copy.db --migrate

  Options:

    * `--database PATH`: the SQLite database to check, instead of the
      configured one.
    * `--migrate`: runs the pending migrations on it first.

  Copy a database with `sqlite3 prod.db ".backup /tmp/prod-copy.db"`, not
  `cp`: it is in WAL mode, and a plain copy can miss the latest writes.

  Exits with status 1 if there is any issue.
  """
  use Mix.Task

  alias FGDataCatalog.Changelog.Verify
  alias FGDataCatalog.Repo

  @impl true
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: [database: :string, migrate: :boolean])

    Mix.Task.run("app.config")
    Logger.configure(level: :warning)

    if path = opts[:database] do
      unless File.exists?(path), do: Mix.raise("no database at #{path}")
      config = Application.get_env(:fg_data_catalog, Repo, [])
      Application.put_env(:fg_data_catalog, Repo, Keyword.put(config, :database, path))
    end

    {:ok, result, _apps} =
      Ecto.Migrator.with_repo(Repo, fn repo ->
        if opts[:migrate], do: Ecto.Migrator.run(repo, :up, all: true)
        Verify.run()
      end)

    Verify.print(result)
    if result != :ok, do: exit({:shutdown, 1})
  end
end
