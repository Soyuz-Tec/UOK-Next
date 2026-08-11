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

    response =
      conn
      |> put_req_header("authorization", "Bearer #{@token}")
      |> get(~p"/api/v1/metrics")
      |> response(200)

    assert response =~ "uok_next_command_stop_duration"
    assert response =~ "master.parties.create_draft"
  end
end
