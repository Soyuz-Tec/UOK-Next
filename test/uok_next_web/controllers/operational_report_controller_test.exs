defmodule UokNextWeb.OperationalReportControllerTest do
  use UokNextWeb.ConnCase, async: true

  alias UokNext.OperationalReportingFixtures
  alias UokNext.ProcurementFixtures

  @access_code "uok-next-test-access-code-00000001"
  @tenant_id "11111111-1111-4111-8111-111111111111"
  @actor_id "22222222-2222-4222-8222-222222222222"

  test "serves one no-store reconciled operational report", %{conn: conn} do
    context =
      ProcurementFixtures.context(%{
        tenant_id: @tenant_id,
        actor_id: @actor_id,
        permissions: ProcurementFixtures.permissions()
      })

    source = OperationalReportingFixtures.completed_readiness(context)
    token = sign_in(conn)

    response =
      build_conn()
      |> authenticated(token)
      |> get(
        ~p"/api/v1/operational-reports/#{source.readiness["id"]}?expected_version=#{source.readiness["lock_version"]}"
      )

    assert response.status == 200
    assert get_resp_header(response, "cache-control") == ["no-store"]
    report = response |> json_response(200) |> Map.fetch!("data")
    assert report["grain"]["id"] == source.readiness["id"]
    assert report["reconciliation"]["projection_sha256"] == report["projection_id"]
    assert report["authority"]["business_mutation_authorized"] == false
    assert report["authority"]["external_effect_created"] == false
  end

  test "rejects missing or malformed exact version and unauthenticated access", %{conn: conn} do
    token = sign_in(conn)
    id = Ecto.UUID.generate()

    assert build_conn()
           |> authenticated(token)
           |> get(~p"/api/v1/operational-reports/#{id}")
           |> json_response(400)
           |> get_in(["error", "code"]) == "invalid_request"

    assert build_conn()
           |> authenticated(token)
           |> get(~p"/api/v1/operational-reports/#{id}?expected_version=0")
           |> json_response(400)
           |> get_in(["error", "code"]) == "invalid_request"

    assert conn
           |> get(~p"/api/v1/operational-reports/#{id}?expected_version=1")
           |> json_response(401)
           |> get_in(["error", "code"]) == "unauthorized"
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
