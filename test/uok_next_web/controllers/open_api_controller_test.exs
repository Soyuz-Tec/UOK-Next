defmodule UokNextWeb.OpenApiControllerTest do
  use UokNextWeb.ConnCase, async: true

  test "publishes the versioned Gate 3 command contract", %{conn: conn} do
    contract = conn |> get(~p"/api/v1/openapi.json") |> json_response(200)

    assert contract["openapi"] == "3.1.0"
    assert Map.has_key?(contract["paths"], "/parties/{id}/evidence")
    assert Map.has_key?(contract["paths"], "/products")
    assert Map.has_key?(contract["paths"], "/locations")
    assert Map.has_key?(contract["paths"], "/sourcing-lanes/{id}/evidence")
    assert Map.has_key?(contract["paths"], "/purchase-requisitions")
    assert Map.has_key?(contract["paths"], "/rfqs")
    assert Map.has_key?(contract["paths"], "/supplier-quotes/{id}/evidence")
    assert Map.has_key?(contract["paths"], "/quote-comparisons/{id}/decision")
    assert Map.has_key?(contract["paths"], "/purchase-commitment-proposals")
    assert Map.has_key?(contract["paths"], "/purchase-commitment-proposals/{id}/evidence")
    assert Map.has_key?(contract["paths"], "/purchase-commitment-proposals/{id}/decision")
    assert contract["info"]["version"] == "0.4.0"
    assert contract["components"]["securitySchemes"]["bearerAuth"]["scheme"] == "bearer"
  end
end
