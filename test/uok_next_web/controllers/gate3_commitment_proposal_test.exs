defmodule UokNextWeb.Gate3CommitmentProposalTest do
  use UokNextWeb.ConnCase, async: true

  alias UokNext.ProcurementFixtures

  @access_code "uok-next-test-access-code-00000001"
  @tenant_id "11111111-1111-4111-8111-111111111111"
  @actor_id "22222222-2222-4222-8222-222222222222"

  test "delivers the source-derived proposal, evidence, and exact decision API", %{conn: conn} do
    context =
      ProcurementFixtures.context(%{
        tenant_id: @tenant_id,
        actor_id: @actor_id,
        permissions: ProcurementFixtures.permissions()
      })

    source = ProcurementFixtures.approved_comparison(context)
    token = sign_in(conn)
    request_key = Ecto.UUID.generate()

    attrs = %{
      "stable_identifier" => "proposal-#{System.unique_integer([:positive])}",
      "quote_comparison_id" => source.comparison["id"],
      "expected_comparison_version" => source.comparison["lock_version"],
      "reason" => "Create one source-derived non-binding proposal"
    }

    rejected =
      build_conn()
      |> authenticated(token, Ecto.UUID.generate())
      |> post(~p"/api/v1/purchase-commitment-proposals", Map.put(attrs, "unit_price", "0.01"))

    assert rejected.status == 422

    created_conn =
      build_conn()
      |> authenticated(token, request_key)
      |> post(~p"/api/v1/purchase-commitment-proposals", attrs)

    assert created_conn.status == 201
    assert get_resp_header(created_conn, "idempotency-status") == ["executed"]
    proposal = created_conn |> json_response(201) |> Map.fetch!("data")

    replay_conn =
      build_conn()
      |> authenticated(token, request_key)
      |> post(~p"/api/v1/purchase-commitment-proposals", attrs)

    assert replay_conn.status == 200
    assert get_resp_header(replay_conn, "idempotency-status") == ["replayed"]
    assert replay_conn |> json_response(200) |> Map.fetch!("data") == proposal
    assert proposal["selected_quote_id"] == source.selected_quote["id"]
    refute proposal["commitment_created"]

    submitted =
      build_conn()
      |> authenticated(token, Ecto.UUID.generate())
      |> post(~p"/api/v1/purchase-commitment-proposals/#{proposal["id"]}/evidence", %{
        "evidence_id" => Ecto.UUID.generate(),
        "expected_version" => proposal["lock_version"],
        "classification" => "confidential",
        "reason" => "Attach reviewed internal proposal evidence",
        "file" => upload_fixture("approved source and internal commitment rationale")
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert submitted["status"] == "awaiting_review"

    approved =
      build_conn()
      |> authenticated(token, Ecto.UUID.generate())
      |> post(~p"/api/v1/purchase-commitment-proposals/#{proposal["id"]}/decision", %{
        "decision" => "approve",
        "reason" => "Approve the exact internal proposal",
        "task_id" => submitted["review_task"]["id"],
        "expected_version" => submitted["lock_version"]
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert approved["status"] == "approved"
    assert approved["review_task"]["resolution"] == "approve"
    refute approved["commitment_created"]
    refute approved["external_effect_created"]

    assert [listed] =
             build_conn()
             |> authenticated(token)
             |> get(~p"/api/v1/purchase-commitment-proposals?limit=100")
             |> json_response(200)
             |> Map.fetch!("data")

    assert listed["id"] == approved["id"]
    assert listed["source_snapshot"]["quote_comparison_id"] == source.comparison["id"]
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
    path = Path.join(System.tmp_dir!(), "uok-commitment-#{Ecto.UUID.generate()}.txt")
    File.write!(path, content, [:binary])
    on_exit(fn -> File.rm(path) end)
    %Plug.Upload{path: path, filename: "proposal-evidence.txt", content_type: "text/plain"}
  end
end
