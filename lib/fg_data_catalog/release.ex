defmodule FGDataCatalog.Release do
  @moduledoc """
  Database tasks of a production deploy, run by `deploy/vm/fgdc-deploy` with
  `bin/fg_data_catalog eval`, while the app is stopped (see `deploy/README.md`):

    * `backup/1`: a consistent copy of the SQLite database, before anything
      else.
    * `rollback_for/1`: run with the release being left, undoes the
      migrations that the target release does not know (going back to an
      older release). Only the newer code has their `down`.
    * `migrate_and_verify/0`: run with the target release, applies its
      pending migrations and checks the changelog against its schemas
      (`FGDataCatalog.Changelog.Verify`). Also run on a database sent to
      replace the production one (`deploy/fgdc replace-db`).

  Each one prints what it does, and halts with status 1 on failure, so that
  the deploy restores the backup and the previous release.

  NOTE(Claude Opus 5.5 2026-11-18): migrations only run here, never when the
  app starts (see `FGDataCatalog.Application`), so that there is always a
  backup before them.
  """

  alias FGDataCatalog.Changelog.Verify
  alias FGDataCatalog.Repo

  @doc "Writes a copy of the database to `path` (`VACUUM INTO`), which must not exist."
  def backup(path) do
    run(fn ->
      if File.exists?(path), do: raise("#{path} already exists")
      Repo.query!("VACUUM INTO ?", [path])
      IO.puts("Backed up #{database()} to #{path}")
    end)
  end

  @doc """
  Rolls back the applied migrations that are not in `migrations_dir` (the
  target release's `priv/repo/migrations`), newest first.

  Refuses to roll back every applied migration (the target would start from
  an empty database: e.g. migrations squashed after the first deploy), and to
  run if the database has migrations this release does not know (it is not
  the newer of the two).
  """
  def rollback_for(migrations_dir) do
    run(fn ->
      known = migration_versions(migrations_dir)
      statuses = Ecto.Migrator.migrations(Repo)
      applied = for {:up, version, _name} <- statuses, do: version
      refuse_unknown_migrations!(statuses)

      case Enum.reject(applied, &(&1 in known)) do
        [] ->
          IO.puts("No migration to roll back for #{migrations_dir}")

        unknown ->
          to = Enum.min(unknown)

          if Enum.all?(applied, &(&1 >= to)),
            do: raise("refusing to roll back every migration (#{inspect(applied)})")

          IO.puts("Rolling back the migrations from #{to} on: #{inspect(Enum.sort(unknown))}")
          Ecto.Migrator.run(Repo, :down, to: to)
      end
    end)
  end

  @doc """
  Applies the pending migrations, then checks the changelog. Refuses a
  database with migrations this release does not know.
  """
  # NOTE(Claude Opus 5.5 2026-11-19): the refusal for a database sent by
  # `deploy/fgdc replace-db` (e.g. the dev one, migrated ahead of the release
  # running in production): Ecto would ignore those migrations and the
  # release would run on columns it does not know. After a deploy or a
  # rollback (`rollback_for/1`), there are none.
  def migrate_and_verify do
    run(fn ->
      refuse_unknown_migrations!(Ecto.Migrator.migrations(Repo))
      Ecto.Migrator.run(Repo, :up, all: true)
      result = Verify.run()
      Verify.print(result)
      if result != :ok, do: raise("the changelog does not fit the tables")
    end)
  end

  # NOTE(Claude Opus 5.5 2026-11-18): the repo alone (no endpoint), as with
  # `Verify.main/0`; any exception halts with status 1. One connection: two
  # would race to switch a database that is not in WAL mode yet (a restored
  # backup) to it, and one fails with "database is locked".
  defp run(fun) do
    Application.load(:fg_data_catalog)

    try do
      {:ok, _, _apps} = Ecto.Migrator.with_repo(Repo, fn _repo -> fun.() end, pool_size: 1)
      System.halt(0)
    rescue
      exception ->
        IO.puts(:stderr, "Failed: " <> Exception.message(exception))
        System.halt(1)
    end
  end

  defp database, do: Repo.config()[:database]

  defp refuse_unknown_migrations!(statuses) do
    case for({:up, version, "** FILE NOT FOUND **"} <- statuses, do: version) do
      [] ->
        :ok

      missing ->
        raise "the database has migrations this release does not know: #{inspect(missing)}"
    end
  end

  defp migration_versions(dir) do
    unless File.dir?(dir), do: raise("no migrations directory at #{dir}")

    for file <- File.ls!(dir),
        [_, version] <- [Regex.run(~r/^(\d+)_.*\.exs$/, file)],
        do: String.to_integer(version)
  end
end
