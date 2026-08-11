defmodule UokNextWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://telemetry-metrics.hexdocs.pm
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000},
      {TelemetryMetricsPrometheus.Core,
       name: :uok_next_metrics, metrics: metrics(), start_async: false}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      distribution("phoenix.endpoint.stop.duration",
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1_000]],
        unit: {:native, :millisecond}
      ),
      distribution("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1_000]],
        unit: {:native, :millisecond}
      ),
      distribution("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1_000]],
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),

      # Database Metrics
      distribution("uok_next.repo.query.total_time",
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1_000]],
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      distribution("uok_next.repo.query.query_time",
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1_000]],
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      distribution("uok_next.repo.query.queue_time",
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1_000]],
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),

      # Kernel command metrics
      counter("uok_next.command.stop.count", tags: [:command, :outcome]),
      distribution("uok_next.command.stop.duration",
        tags: [:command, :outcome],
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1_000]],
        unit: {:native, :millisecond}
      ),
      # VM Metrics
      last_value("vm.memory.total", unit: {:byte, :kilobyte}),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements, do: []
end
