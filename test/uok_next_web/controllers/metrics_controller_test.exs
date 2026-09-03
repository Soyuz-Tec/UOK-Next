defmodule UokNextWeb.MetricsControllerTest do
  use UokNextWeb.ConnCase, async: true

  @token "uok-next-test-metrics-token-only"

  test "fails closed without the configured bearer token", %{conn: conn} do
    assert conn |> get(~p"/api/v1/metrics") |> response(404) == "not found"

    assert conn
           |> recycle()
           |> put_req_header("authorization", "Bearer #{String.duplicate("x", 32)}")
           |> get(~p"/api/v1/metrics")
           |> response(404) == "not found"

    assert conn
           |> recycle()
           |> put_req_header("authorization", "Bearer #{String.duplicate("x", 257)}")
           |> get(~p"/api/v1/metrics")
           |> response(404) == "not found"
  end

  test "exports bounded Prometheus telemetry to an authorized scraper", %{conn: conn} do
    :telemetry.execute(
      [:uok_next, :command, :stop],
      %{duration: System.convert_time_unit(8, :millisecond, :native)},
      %{command: "master.parties.create_draft", outcome: "executed"}
    )

    :telemetry.execute(
      [:uok_next, :durable_work, :stop],
      %{duration: System.convert_time_unit(3, :millisecond, :native)},
      %{job: "kernel.outbox.publish", outcome: "published"}
    )

    :telemetry.execute(
      [:uok_next, :durable_work, :recovery],
      %{count: 1},
      %{job: "kernel.outbox.publish", outcome: "completed"}
    )

    response =
      conn
      |> put_req_header("authorization", "Bearer #{@token}")
      |> get(~p"/api/v1/metrics")
      |> response(200)

    assert response =~ "uok_next_command_stop_duration"
    assert response =~ "master.parties.create_draft"
    assert response =~ "uok_next_durable_work_stop_duration"
    assert response =~ "uok_next_durable_work_recovery_count"
    assert response =~ "kernel.outbox.publish"
  end
end
