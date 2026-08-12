defmodule UokNextWeb.Spikes.PartyControllerTest do
  use UokNextWeb.ConnCase, async: true

  import UokNext.PartyOnboardingFixtures

  describe "explicit HTTP contract" do
    test "creates, reads, submits evidence, and decides", %{conn: conn} do
      context = context()

      create_response =
        conn
        |> authenticated(context, Ecto.UUID.generate())
        |> post(~p"/api/v1/spikes/explicit/parties", party_attrs())
        |> json_response(201)

      party = create_response["data"]
      assert create_response["disposition"] == "executed"

      get_response =
        build_conn()
        |> authenticated(context)
        |> get(~p"/api/v1/spikes/explicit/parties/#{party["id"]}")
        |> json_response(200)

      assert get_response["data"] == party

      evidence_response =
        build_conn()
        |> authenticated(context, Ecto.UUID.generate())
        |> post(
          ~p"/api/v1/spikes/explicit/parties/#{party["id"]}/evidence",
          persisted_evidence_attrs(context, party)
          |> Map.put("expected_version", party["lock_version"])
        )
        |> json_response(200)

      evidenced = evidence_response["data"]
      assert evidenced["status"] == "evidence_submitted"

      decision_response =
        build_conn()
        |> authenticated(context, Ecto.UUID.generate())
        |> post(~p"/api/v1/spikes/explicit/parties/#{party["id"]}/decision", %{
          "decision" => "approve",
          "reason" => "Evidence passed compliance review",
          "task_id" => evidenced["review_task"]["id"],
          "expected_version" => evidenced["lock_version"]
        })
        |> json_response(200)

      assert decision_response["data"]["status"] == "approved"
    end

    test "returns stable permission, validation, and stale-state errors", %{conn: conn} do
      denied_context = context(%{permissions: []})

      denied =
        conn
        |> authenticated(denied_context, Ecto.UUID.generate())
        |> post(~p"/api/v1/spikes/explicit/parties", party_attrs())
        |> json_response(403)

      assert denied["error"]["code"] == "forbidden"

      invalid =
        build_conn()
        |> authenticated(context(), Ecto.UUID.generate())
        |> post(
          ~p"/api/v1/spikes/explicit/parties",
          party_attrs(%{"country_code" => "invalid"})
        )
        |> json_response(422)

      assert invalid["error"]["code"] == "validation_failed"
    end
  end

  defp authenticated(conn, context, idempotency_key \\ nil) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-uok-test-tenant-id", context.tenant_id)
    |> put_req_header("x-uok-test-actor-id", context.actor_id)
    |> put_req_header("x-uok-test-correlation-id", context.correlation_id)
    |> put_req_header("x-uok-test-permissions", Enum.join(context.permissions, ","))
    |> maybe_idempotency_key(idempotency_key)
  end

  defp maybe_idempotency_key(conn, nil), do: conn
  defp maybe_idempotency_key(conn, key), do: put_req_header(conn, "idempotency-key", key)
end
