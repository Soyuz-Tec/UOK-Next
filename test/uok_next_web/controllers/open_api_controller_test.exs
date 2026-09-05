defmodule UokNextWeb.OpenApiControllerTest do
  use UokNextWeb.ConnCase, async: true

  test "publishes the versioned business and communications contracts", %{conn: conn} do
    contract = conn |> get(~p"/api/v1/openapi.json") |> json_response(200)

    assert contract["openapi"] == "3.1.0"
    assert Map.has_key?(contract["paths"], "/session/password")
    assert Map.has_key?(contract["paths"], "/identity/users")
    assert Map.has_key?(contract["paths"], "/identity/access-profiles")
    assert Map.has_key?(contract["paths"], "/communications/health")
    assert Map.has_key?(contract["paths"], "/communication-links")
    assert Map.has_key?(contract["paths"], "/communication-links/{id}")
    assert Map.has_key?(contract["paths"], "/communication-links/{id}/deliveries")

    assert Map.has_key?(
             contract["paths"],
             "/communication-links/{id}/deliveries/{receipt_id}/reconcile"
           )

    assert Map.has_key?(contract["paths"], "/parties/{id}/evidence")
    assert Map.has_key?(contract["paths"], "/products")
    assert Map.has_key?(contract["paths"], "/locations")
    assert Map.has_key?(contract["paths"], "/location-references/major-seaports")
    assert Map.has_key?(contract["paths"], "/location-references/major-seaports/countries")
    assert Map.has_key?(contract["paths"], "/sourcing-lanes/{id}/evidence")
    assert Map.has_key?(contract["paths"], "/purchase-requisitions")
    assert Map.has_key?(contract["paths"], "/rfqs")
    assert Map.has_key?(contract["paths"], "/supplier-quotes/{id}/evidence")
    assert Map.has_key?(contract["paths"], "/quote-comparisons/{id}/decision")
    assert Map.has_key?(contract["paths"], "/purchase-commitment-proposals")
    assert Map.has_key?(contract["paths"], "/purchase-commitment-proposals/{id}/evidence")
    assert Map.has_key?(contract["paths"], "/purchase-commitment-proposals/{id}/decision")
    assert Map.has_key?(contract["paths"], "/shipment-readiness-cases")
    assert Map.has_key?(contract["paths"], "/shipment-readiness-cases/{id}/evidence")
    assert Map.has_key?(contract["paths"], "/shipment-readiness-cases/{id}/decision")
    assert Map.has_key?(contract["paths"], "/operational-reports/{id}")
    assert contract["info"]["version"] == "0.8.0"
    assert contract["components"]["securitySchemes"]["bearerAuth"]["scheme"] == "bearer"
  end
end
