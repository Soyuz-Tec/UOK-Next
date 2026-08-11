defmodule UokNextWeb.HealthControllerTest do
  use UokNextWeb.ConnCase, async: false

  test "GET /api/v1/health returns release identity", %{conn: conn} do
    response_conn = get(conn, ~p"/api/v1/health")
    response = json_response(response_conn, 200)

    assert response["status"] == "ok"
    assert response["service"] == "uok-next"
    assert response["version"] == "0.1.0"
    assert response["revision"] == Application.fetch_env!(:uok_next, :build_revision)
    assert get_resp_header(response_conn, "cache-control") == ["no-store"]
  end

  test "separates liveness, readiness, startup, and release identity", %{conn: conn} do
    live_conn = get(conn, ~p"/api/v1/health/live")
    live = json_response(live_conn, 200)
    assert live["status"] == "live"
    assert get_resp_header(live_conn, "cache-control") == ["no-store"]

    ready = build_conn() |> get(~p"/api/v1/health/ready") |> json_response(200)
    assert ready["status"] == "ready"

    startup = build_conn() |> get(~p"/api/v1/health/startup") |> json_response(200)
    assert startup["status"] == "ready"

    release = build_conn() |> get(~p"/api/v1/release") |> json_response(200)
    assert release["service"] == "uok-next"
    refute Map.has_key?(release, "status")
  end
end
