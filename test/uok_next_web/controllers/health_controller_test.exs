defmodule UokNextWeb.HealthControllerTest do
  use UokNextWeb.ConnCase, async: true

  test "GET /api/v1/health returns release identity", %{conn: conn} do
    response =
      conn
      |> get(~p"/api/v1/health")
      |> json_response(200)

    assert response["status"] == "ok"
    assert response["service"] == "uok-next"
    assert response["version"] == "0.1.0"
    assert is_binary(response["revision"])
  end
end
