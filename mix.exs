defmodule FGDataCatalog.MixProject do
  use Mix.Project

  def project do
    [
      app: :fg_data_catalog,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      # NOTE(Claude Opus 5.5 2026-11-18): built for the production VM by
      # `deploy/fgdc build` (see `deploy/README.md`).
      releases: [fg_data_catalog: [include_executables_for: [:unix]]]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {FGDataCatalog.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.16"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      # NOTE(Claude 2026-11-06): HTTP client, for Google's token endpoint
      # (`FGDataCatalog.Accounts.Google`).
      {:req, "~> 0.5"},
      # NOTE(Claude 2026-11-06): SVG sources of `<.icon>`, read at compile time by
      # `FGDataCatalogWeb.Icons`. Not an Elixir app, never compiled.
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": ["compile", "esbuild fg_data_catalog"],
      "assets.deploy": [
        "esbuild fg_data_catalog --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"],
      # NOTE(Claude Opus 5.5 2026-11-18): shortcuts to `deploy/fgdc` (see
      # `deploy/README.md`); arguments are passed on, e.g.
      # `mix deploy.rollback --restore-backup`.
      deploy: ["cmd deploy/fgdc deploy"],
      "deploy.rollback": ["cmd deploy/fgdc rollback"],
      # NOTE(Claude Opus 5.5 2026-11-19): replace the production database
      # (default: with the dev one), or put back one of its backups.
      # NOTE(Claude Opus 5.5 2026-11-19): `mix cmd` runs the script without a
      # terminal, so `deploy.replace_db` cannot ask for confirmation: pass
      # `--yes`, or run `deploy/fgdc replace-db` to be asked.
      "deploy.replace_db": ["cmd deploy/fgdc replace-db"],
      "deploy.restore_backup": ["cmd deploy/fgdc restore-backup"],
      "deploy.status": ["cmd deploy/fgdc status"]
    ]
  end
end
