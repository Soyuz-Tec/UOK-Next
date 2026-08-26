defmodule UokNextWeb.Gate3PartyOnboardingTest do
  use UokNextWeb.ConnCase, async: false

  alias UokNext.Kernel.{
    AuditEvent,
    CommandContext,
    CommandReceipt,
    OutboxEvent,
    TenantTransaction
  }

  alias UokNext.Modules.Master.Parties.Infrastructure.PartyRecord
  alias UokNext.Modules.Platform.Evidence.Infrastructure.EvidenceCandidateRecord
  alias UokNext.Modules.Platform.Workflow.Infrastructure.HumanTaskRecord
  alias UokNext.Repo

  @access_code "uok-next-test-access-code-00000001"

  test "completes authenticated party onboarding through API, bytes, task, audit, and outbox", %{
    conn: conn
  } do
    token = sign_in(conn)
    party = create_party(token)
    evidence_id = Ecto.UUID.generate()
    evidence_key = Ecto.UUID.generate()
    upload = upload_fixture("registration evidence")

    evidenced = upload_evidence(token, party, evidence_id, evidence_key, upload)
    assert evidenced["status"] == "evidence_submitted"
    assert evidenced["evidence_metadata"]["evidence_id"] == evidence_id
    assert evidenced["review_task"]["status"] == "open"

    replayed = upload_evidence(token, party, evidence_id, evidence_key, upload)
    assert replayed == evidenced

    tasks =
      build_conn()
      |> authenticated(token)
      |> get(~p"/api/v1/review-tasks")
      |> json_response(200)
      |> Map.fetch!("data")

    assert [%{"id" => task_id, "subject_id" => subject_id}] = tasks
    assert subject_id == party["id"]

    approved =
      build_conn()
      |> authenticated(token, Ecto.UUID.generate())
      |> post(~p"/api/v1/parties/#{party["id"]}/decision", %{
        "decision" => "approve",
        "reason" => "Verified registration evidence is sufficient",
        "task_id" => task_id,
        "expected_version" => evidenced["lock_version"]
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert approved["status"] == "approved"
    assert approved["review_task"]["resolution"] == "approve"

    detail =
      build_conn()
      |> authenticated(token)
      |> get(~p"/api/v1/parties/#{party["id"]}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert detail["status"] == "approved"
    assert [%{"id" => ^evidence_id, "state" => "verified"}] = detail["evidence_objects"]

    context = qualification_context()
    assert tenant_count(PartyRecord, context) == 1
    assert tenant_count(EvidenceCandidateRecord, context) == 1
    assert tenant_count(HumanTaskRecord, context) == 1
    assert tenant_count(CommandReceipt, context) == 6
    assert tenant_count(AuditEvent, context) == 8
    assert tenant_count(OutboxEvent, context) == 8
  end

  test "rejects missing authentication, invalid access, stale state, and unsupported uploads", %{
    conn: conn
  } do
    assert conn |> get(~p"/api/v1/parties") |> json_response(401) == %{
             "error" => %{"code" => "unauthorized", "message" => "authentication failed"}
           }

    invalid_login =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/session", %{"access_code" => String.duplicate("x", 32)})
      |> json_response(401)

    assert invalid_login["error"]["code"] == "unauthorized"

    token = sign_in(build_conn())
    party = create_party(token)
    upload = upload_fixture("unsupported", "application/x-invalid")

    rejected =
      build_conn()
      |> authenticated(token, Ecto.UUID.generate())
      |> post(~p"/api/v1/parties/#{party["id"]}/evidence", %{
        "evidence_id" => Ecto.UUID.generate(),
        "expected_version" => party["lock_version"],
        "classification" => "confidential",
        "reason" => "Attempt unsupported evidence content",
        "file" => upload
      })
      |> json_response(422)

    assert rejected["error"]["code"] == "invalid_upload"

    stale =
      build_conn()
      |> authenticated(token, Ecto.UUID.generate())
      |> post(~p"/api/v1/parties/#{party["id"]}/decision", %{
        "decision" => "approve",
        "reason" => "No evidence or task exists",
        "task_id" => Ecto.UUID.generate(),
        "expected_version" => party["lock_version"] + 1
      })
      |> json_response(409)

    assert stale["error"]["code"] == "stale_state"
  end

  test "rejects unknown and stale parties before persisting evidence", %{conn: conn} do
    token = sign_in(conn)
    context = qualification_context()
    unknown_party_id = Ecto.UUID.generate()

    unknown =
      build_conn()
      |> authenticated(token, Ecto.UUID.generate())
      |> post(~p"/api/v1/parties/#{unknown_party_id}/evidence", %{
        "evidence_id" => Ecto.UUID.generate(),
        "expected_version" => 1,
        "classification" => "confidential",
        "reason" => "Attempt evidence for an unknown party",
        "file" => upload_fixture("unknown party evidence")
      })
      |> json_response(404)

    assert unknown["error"]["code"] == "not_found"
    assert tenant_count(EvidenceCandidateRecord, context) == 0

    party = create_party(token)

    stale =
      build_conn()
      |> authenticated(token, Ecto.UUID.generate())
      |> post(~p"/api/v1/parties/#{party["id"]}/evidence", %{
        "evidence_id" => Ecto.UUID.generate(),
        "expected_version" => party["lock_version"] + 1,
        "classification" => "confidential",
        "reason" => "Attempt evidence with a stale party version",
        "file" => upload_fixture("stale party evidence")
      })
      |> json_response(409)

    assert stale["error"]["code"] == "stale_state"
    assert tenant_count(EvidenceCandidateRecord, context) == 0
  end

  defp sign_in(conn) do
    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/session", %{"access_code" => @access_code})
      |> json_response(201)
      |> Map.fetch!("data")

    assert response["token_type"] == "Bearer"
    response["access_token"]
  end

  defp create_party(token) do
    response =
      build_conn()
      |> authenticated(token, Ecto.UUID.generate())
      |> post(~p"/api/v1/parties", %{
        "stable_identifier" => "supplier-#{System.unique_integer([:positive])}",
        "legal_name" => "Aseda Trading Limited",
        "country_code" => "GH",
        "party_kind" => "organization",
        "reason" => "Begin governed supplier onboarding"
      })
      |> json_response(201)

    assert response["data"]["status"] == "draft"
    response["data"]
  end

  defp upload_evidence(token, party, evidence_id, key, upload) do
    build_conn()
    |> authenticated(token, key)
    |> post(~p"/api/v1/parties/#{party["id"]}/evidence", %{
      "evidence_id" => evidence_id,
      "expected_version" => party["lock_version"],
      "classification" => "confidential",
      "reason" => "Attach verified registration evidence",
      "file" => upload
    })
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp authenticated(conn, token, idempotency_key \\ nil) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("accept", "application/json")
    |> maybe_idempotency(idempotency_key)
  end

  defp maybe_idempotency(conn, nil), do: conn
  defp maybe_idempotency(conn, key), do: put_req_header(conn, "idempotency-key", key)

  defp upload_fixture(content, content_type \\ "text/plain") do
    path = Path.join(System.tmp_dir!(), "uok-evidence-#{Ecto.UUID.generate()}.txt")
    File.write!(path, content, [:binary])
    on_exit(fn -> File.rm(path) end)
    %Plug.Upload{path: path, filename: "evidence.txt", content_type: content_type}
  end

  defp qualification_context do
    identity = Application.fetch_env!(:uok_next, :local_qualification_identity)

    {:ok, context} =
      CommandContext.new(%{
        tenant_id: identity.tenant_id,
        actor_id: identity.actor_id,
        correlation_id: Ecto.UUID.generate(),
        permissions: identity.permissions
      })

    context
  end

  defp tenant_count(schema, context) do
    {:ok, count} =
      TenantTransaction.run(context, fn -> {:ok, Repo.aggregate(schema, :count)} end)

    count
  end
end
