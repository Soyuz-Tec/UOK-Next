defmodule UokNextWeb.Gate3ShipmentReadinessTest do
  use UokNextWeb.ConnCase, async: true

  alias UokNext.ProcurementFixtures

  @access_code "uok-next-test-access-code-00000001"
  @tenant_id "11111111-1111-4111-8111-111111111111"
  @actor_id "22222222-2222-4222-8222-222222222222"
  @effect_flags ~w(shipment_created dispatch_created inventory_effect_created finance_effect_created external_effect_created)

  test "delivers the source-derived readiness, evidence, and exact GO API", %{conn: conn} do
    context =
      ProcurementFixtures.context(%{
        tenant_id: @tenant_id,
        actor_id: @actor_id,
        permissions: ProcurementFixtures.permissions()
      })

    source = ProcurementFixtures.approved_proposal(context)
    token = sign_in(conn)
    request_key = Ecto.UUID.generate()

    attrs = %{
      "stable_identifier" => "readiness-#{System.unique_integer([:positive])}",
      "purchase_commitment_proposal_id" => source.proposal["id"],
      "expected_proposal_version" => source.proposal["lock_version"],
      "reason" => "Create one source-derived readiness case"
    }

    rejected =
      build_conn()
      |> authenticated(token, Ecto.UUID.generate())
      |> post(~p"/api/v1/shipment-readiness-cases", Map.put(attrs, "checklist_snapshot", %{}))

    assert rejected.status == 422

    created_conn =
      build_conn()
      |> authenticated(token, request_key)
      |> post(~p"/api/v1/shipment-readiness-cases", attrs)

    assert created_conn.status == 201
    assert get_resp_header(created_conn, "idempotency-status") == ["executed"]
    readiness = created_conn |> json_response(201) |> Map.fetch!("data")

    replay_conn =
      build_conn()
      |> authenticated(token, request_key)
      |> post(~p"/api/v1/shipment-readiness-cases", attrs)

    assert replay_conn.status == 200
    assert get_resp_header(replay_conn, "idempotency-status") == ["replayed"]
    assert replay_conn |> json_response(200) |> Map.fetch!("data") == readiness
    assert readiness["purchase_commitment_proposal_id"] == source.proposal["id"]
    assert_no_effects(readiness)

    submitted =
      build_conn()
      |> authenticated(token, Ecto.UUID.generate())
      |> post(~p"/api/v1/shipment-readiness-cases/#{readiness["id"]}/evidence", %{
        "evidence_id" => Ecto.UUID.generate(),
        "expected_version" => readiness["lock_version"],
        "classification" => "confidential",
        "reason" => "Attach reviewed shipment-readiness evidence",
        "file" => upload_fixture("transport capacity, cargo preparation, and document review")
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert submitted["status"] == "awaiting_review"
    assert Enum.all?(submitted["checklist_snapshot"]["checks"], &(&1["status"] == "passed"))

    ready =
      build_conn()
      |> authenticated(token, Ecto.UUID.generate())
      |> post(~p"/api/v1/shipment-readiness-cases/#{readiness["id"]}/decision", %{
        "decision" => "go",
        "reason" => "Record exact shipment-readiness GO",
        "task_id" => submitted["review_task"]["id"],
        "expected_version" => submitted["lock_version"]
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert ready["status"] == "go"
    assert ready["review_task"]["resolution"] == "approve"
    assert_no_effects(ready)

    assert [listed] =
             build_conn()
             |> authenticated(token)
             |> get(~p"/api/v1/shipment-readiness-cases?limit=100")
             |> json_response(200)
             |> Map.fetch!("data")

    assert listed["id"] == ready["id"]
    assert listed["source_snapshot"]["purchase_commitment_proposal_id"] == source.proposal["id"]
  end

  defp sign_in(conn) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(~p"/api/v1/session", %{"access_code" => @access_code})
    |> json_response(201)
    |> get_in(["data", "access_token"])
  end

  defp authenticated(conn, token, key \\ nil) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("accept", "application/json")
    |> then(fn scoped ->
      if key, do: put_req_header(scoped, "idempotency-key", key), else: scoped
    end)
  end

  defp upload_fixture(content) do
    path = Path.join(System.tmp_dir!(), "uok-readiness-#{Ecto.UUID.generate()}.txt")
    File.write!(path, content, [:binary])
    on_exit(fn -> File.rm(path) end)
    %Plug.Upload{path: path, filename: "readiness-evidence.txt", content_type: "text/plain"}
  end

  defp assert_no_effects(view), do: Enum.each(@effect_flags, &refute(view[&1]))
end
