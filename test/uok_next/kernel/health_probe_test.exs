defmodule UokNext.Kernel.HealthProbeTest do
  use ExUnit.Case, async: false

  alias UokNext.Kernel.HealthProbe

  test "serializes and caches admitted checks while rejecting excess concurrency" do
    table = :"uok_next_health_probe_test_#{System.unique_integer([:positive])}"
    counter = start_supervised!({Agent, fn -> 0 end})

    check = fn ->
      Agent.update(counter, &(&1 + 1))
      Process.sleep(100)
      {:ok, %{service: "uok-next", status: "ready"}}
    end

    probe =
      start_supervised!(
        {HealthProbe, name: nil, table: table, check: check, ttl_ms: 1_000, max_inflight: 2}
      )

    results =
      1..20
      |> Enum.map(fn _index -> Task.async(fn -> HealthProbe.readiness(probe, table) end) end)
      |> Task.await_many(5_000)

    assert Agent.get(counter, & &1) == 1
    assert Enum.any?(results, &match?({:ok, %{status: "ready"}}, &1))
    assert Enum.any?(results, &match?({:error, %{reason: "probe_busy"}}, &1))

    assert Enum.all?(results, fn
             {:ok, _response} -> true
             {:error, _response} -> true
           end)
  end

  test "fails closed when the probe process is unavailable" do
    table = :"uok_next_health_probe_test_#{System.unique_integer([:positive])}"
    {:ok, probe} = HealthProbe.start_link(name: nil, table: table)
    GenServer.stop(probe)

    assert {:error, %{reason: "probe_unavailable"}} = HealthProbe.readiness(probe, table)
  end
end
