defmodule UokNext.Kernel.HealthProbe do
  @moduledoc """
  Serializes, caches, and admission-limits database-backed health probes.

  Orchestrators can poll readiness aggressively without turning an unauthenticated
  operational endpoint into an unbounded database workload.
  """

  use GenServer

  alias UokNext.Kernel.Health

  @default_table :uok_next_health_probe_admission
  @default_ttl_ms 1_000
  @default_max_inflight 8
  @call_timeout 2_500

  @type check_result :: {:ok, map()} | {:error, map()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options \\ []) do
    name = Keyword.get(options, :name, __MODULE__)
    genserver_options = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, options, genserver_options)
  end

  @spec readiness(GenServer.server(), atom()) :: check_result()
  def readiness(server \\ __MODULE__, table \\ @default_table) do
    case admit(table) do
      :ok ->
        try do
          GenServer.call(server, :readiness, @call_timeout)
        catch
          :exit, _reason -> unavailable("probe_unavailable")
        after
          release_admission(table)
        end

      :busy ->
        unavailable("probe_busy")

      :unavailable ->
        unavailable("probe_unavailable")
    end
  end

  @impl true
  def init(options) do
    table = Keyword.get(options, :table, @default_table)
    ttl_ms = Keyword.get(options, :ttl_ms, @default_ttl_ms)
    max_inflight = Keyword.get(options, :max_inflight, @default_max_inflight)
    check = Keyword.get(options, :check, &Health.readiness/0)

    true = is_integer(ttl_ms) and ttl_ms in 100..60_000
    true = is_integer(max_inflight) and max_inflight in 1..100
    true = is_function(check, 0)

    ^table = :ets.new(table, [:named_table, :public, :set, read_concurrency: true])
    true = :ets.insert(table, [{:inflight, 0}, {:max_inflight, max_inflight}])

    {:ok, %{check: check, ttl_ms: ttl_ms, cached_at: nil, cached_result: nil}}
  end

  @impl true
  def handle_call(:readiness, _from, state) do
    now = System.monotonic_time(:millisecond)

    if fresh?(state, now) do
      {:reply, state.cached_result, state}
    else
      result = safe_check(state.check)
      completed_at = System.monotonic_time(:millisecond)
      {:reply, result, %{state | cached_at: completed_at, cached_result: result}}
    end
  end

  defp admit(table) do
    inflight = :ets.update_counter(table, :inflight, {2, 1})
    [{:max_inflight, maximum}] = :ets.lookup(table, :max_inflight)

    if inflight <= maximum do
      :ok
    else
      :ets.update_counter(table, :inflight, {2, -1})
      :busy
    end
  rescue
    ArgumentError -> :unavailable
    MatchError -> :unavailable
  end

  defp fresh?(%{cached_at: nil}, _now), do: false
  defp fresh?(state, now), do: now - state.cached_at < state.ttl_ms

  defp release_admission(table) do
    :ets.update_counter(table, :inflight, {2, -1})
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp safe_check(check) do
    case check.() do
      {:ok, response} when is_map(response) -> {:ok, response}
      {:error, response} when is_map(response) -> {:error, response}
      _invalid -> unavailable("probe_invalid")
    end
  rescue
    _error -> unavailable("probe_unavailable")
  catch
    _kind, _reason -> unavailable("probe_unavailable")
  end

  defp unavailable(reason) do
    {:error, %{service: "uok-next", status: "not_ready", reason: reason}}
  end
end
