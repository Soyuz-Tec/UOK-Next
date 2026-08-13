defmodule UokNextWeb.OpenApiControllerTest do
  use UokNextWeb.ConnCase, async: true

  test "publishes the versioned Gate 3 command contract", %{conn: conn} do
    contract = conn |> get(~p"/api/v1/openapi.json") |> json_response(200)

    assert contract["openapi"] == "3.1.0"
    assert Map.has_key?(contract["paths"], "/parties/{id}/evidence")
    assert Map.has_key?(contract["paths"], "/products")
    assert Map.has_key?(contract["paths"], "/locations")
    assert Map.has_key?(contract["paths"], "/sourcing-lanes/{id}/evidence")
    assert contract["components"]["securitySchemes"]["bearerAuth"]["scheme"] == "bearer"
  end
end
