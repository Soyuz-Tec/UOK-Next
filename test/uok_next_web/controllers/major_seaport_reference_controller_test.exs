defmodule UokNextWeb.MajorSeaportReferenceControllerTest do
  use UokNextWeb.ConnCase, async: true

  @access_code "uok-next-test-access-code-00000001"

  test "serves country choices and standardized ports to an authorized operator", %{conn: conn} do
    token = sign_in(conn)

    country_conn =
      build_conn()
      |> authenticated(token)
      |> get(~p"/api/v1/location-references/major-seaports/countries")

    countries = country_conn |> json_response(200) |> get_in(["data", "items"])
    assert get_resp_header(country_conn, "cache-control") == ["no-store"]
    assert Enum.any?(countries, &(&1["country_code"] == "GH" and &1["port_count"] >= 2))

    response =
      build_conn()
      |> authenticated(token)
      |> get(~p"/api/v1/location-references/major-seaports?country_code=gh")
      |> json_response(200)
      |> Map.fetch!("data")

    assert response["country_code"] == "GH"
    assert Enum.any?(response["items"], &(&1["reference_code"] == "GHTEM"))
  end

  test "fails closed for missing authentication and invalid country input", %{conn: conn} do
    conn
    |> get(~p"/api/v1/location-references/major-seaports?country_code=GH")
    |> json_response(401)

    token = sign_in(build_conn())

    invalid =
      build_conn()
      |> authenticated(token)
      |> get(~p"/api/v1/location-references/major-seaports?country_code=GHA")
      |> json_response(422)

    assert invalid["error"]["code"] == "validation_failed"
  end

  defp sign_in(conn) do
    conn
    |> post(~p"/api/v1/session", %{"access_code" => @access_code})
    |> json_response(201)
    |> get_in(["data", "access_token"])
  end

  defp authenticated(conn, token) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("accept", "application/json")
  end
end
