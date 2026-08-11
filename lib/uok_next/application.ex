defmodule UokNext.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      UokNext.Repo,
      UokNext.Kernel.HealthProbe,
      UokNextWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:uok_next, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: UokNext.PubSub},
      # Start a worker by calling: UokNext.Worker.start_link(arg)
      # {UokNext.Worker, arg},
      # Start to serve requests, typically the last entry
      UokNextWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: UokNext.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    UokNextWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
