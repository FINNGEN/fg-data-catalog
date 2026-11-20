defmodule FGDataCatalog.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FGDataCatalogWeb.Telemetry,
      FGDataCatalog.Repo,
      # NOTE(Claude Opus 5.5 2026-11-18): no `Ecto.Migrator` here: a release
      # would migrate on start, with no backup. The deploy migrates instead
      # (`FGDataCatalog.Release`), after a backup.
      {DNSCluster, query: Application.get_env(:fg_data_catalog, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: FGDataCatalog.PubSub},
      # Start a worker by calling: FGDataCatalog.Worker.start_link(arg)
      # {FGDataCatalog.Worker, arg},
      # Start to serve requests, typically the last entry
      FGDataCatalogWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FGDataCatalog.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FGDataCatalogWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
