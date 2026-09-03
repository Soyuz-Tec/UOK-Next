defmodule UokNext.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    durable_work = Application.fetch_env!(:uok_next, :durable_work)

    children =
      [UokNext.Repo] ++
        durable_repo_children(durable_work) ++
        [UokNext.Kernel.HealthProbe, UokNextWeb.Telemetry] ++
        durable_worker_children(durable_work) ++
        [
          {DNSCluster, query: Application.get_env(:uok_next, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: UokNext.PubSub},
          UokNextWeb.Endpoint
        ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: UokNext.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp durable_repo_children(options) do
    if options[:enabled], do: [options[:repo]], else: []
  end

  defp durable_worker_children(options) do
    if options[:enabled], do: [{UokNext.Kernel.DurableWorkWorker, options}], else: []
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    UokNextWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
