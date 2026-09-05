defmodule UokNextWeb.CommunicationsControllerTest do
  use UokNextWeb.ConnCase, async: false

  alias UokNext.CommunicationsContractDouble
  alias UokNext.Kernel.CommandContext
  alias UokNext.PartyOnboardingFixtures

  @access_code "uok-next-test-access-code-00000001"
  @link_fields ~w(id tenant_id subject_type subject_id subject_version conversation_id lock_version contract_version system_role external_delivery_state)
  @receipt_fields ~w(id tenant_id connector_role operation delivery_key attempt_number request_sha256 subject_type subject_id subject_version status deadline_at previous_receipt_id response_sha256 external_reference retry_after_seconds lock_version communication_link_id contract_acceptance external_delivery_state)

  setup do
    previous = Application.get_env(:uok_next, :communications_adapter)
    start_supervised!(CommunicationsContractDouble)
    Application.put_env(:uok_next, :communications_adapter, CommunicationsContractDouble)

    on_exit(fn ->
      if is_nil(previous),
        do: Application.delete_env(:uok_next, :communications_adapter),
        else: Application.put_env(:uok_next, :communications_adapter, previous)
    end)

    {:ok, token: sign_in(), context: qualification_context()}
  end

  test "all communications routes require an authenticated session" do
    id = Ecto.UUID.generate()
    receipt_id = Ecto.UUID.generate()

    for path <- [~p"/api/v1/communications/health", ~p"/api/v1/communication-links/#{id}"] do
      response = build_conn() |> get(path)
      assert json_response(response, 401)["error"]["code"] == "unauthorized"
      assert get_resp_header(response, "cache-control") == ["no-store"]
    end

    for path <- [
          ~p"/api/v1/communication-links",
          ~p"/api/v1/communication-links/#{id}/deliveries",
          ~p"/api/v1/communication-links/#{id}/deliveries/#{receipt_id}/reconcile"
        ] do
      response = build_conn() |> post(path, %{})
      assert json_response(response, 401)["error"]["code"] == "unauthorized"
    end
  end

  test "the disabled binding reports unavailable and creates no link", %{
    token: token,
    context: context
  } do
    Application.delete_env(:uok_next, :communications_adapter)

    health =
      build_conn()
      |> authenticated(token)
      |> get(~p"/api/v1/communications/health")
      |> json_response(200)
      |> Map.fetch!("data")

    assert health == %{
             "status" => "unavailable",
             "contract_version" => 1,
             "system_role" => "communications_system",
             "external_delivery_state" => "unverified"
           }

    response = create_link(token, link_attrs(context), Ecto.UUID.generate())
    assert json_response(response, 503)["error"]["code"] == "communications_unavailable"
    assert CommunicationsContractDouble.deliveries() == %{}
  end

  test "all commands require an idempotency key before processing", %{token: token} do
    id = Ecto.UUID.generate()
    receipt_id = Ecto.UUID.generate()

    for path <- [
          ~p"/api/v1/communication-links",
          ~p"/api/v1/communication-links/#{id}/deliveries",
          ~p"/api/v1/communication-links/#{id}/deliveries/#{receipt_id}/reconcile"
        ] do
      response = build_conn() |> authenticated(token) |> post(path, %{})
      assert json_response(response, 400)["error"]["code"] == "invalid_idempotency_key"
    end

    assert CommunicationsContractDouble.calls() == %{}
  end

  test "fresh local permissions are required even with a valid session", %{token: token} do
    identity = Application.fetch_env!(:uok_next, :local_qualification_identity)
    permissions = Enum.reject(identity.permissions, &String.starts_with?(&1, "communications:"))

    Application.put_env(:uok_next, :local_qualification_identity, %{
      identity
      | permissions: permissions
    })

    on_exit(fn -> Application.put_env(:uok_next, :local_qualification_identity, identity) end)

    health = build_conn() |> authenticated(token) |> get(~p"/api/v1/communications/health")
    assert json_response(health, 403)["error"]["code"] == "forbidden"

    denied = create_link(token, %{}, Ecto.UUID.generate())
    assert json_response(denied, 403)["error"]["code"] == "forbidden"
    assert CommunicationsContractDouble.calls() == %{}
  end

  test "links and replays reauthorize the independent conversation scope", %{
    token: token,
    context: context
  } do
    attrs = link_attrs(context)
    key = Ecto.UUID.generate()
    denied = create_link(token, attrs, key)
    assert json_response(denied, 403)["error"]["code"] == "communications_denied"

    scope = grant(context, attrs)
    created = create_link(token, attrs, key)
    link = json_response(created, 201)["data"]
    assert get_resp_header(created, "idempotency-status") == ["executed"]
    assert get_resp_header(created, "cache-control") == ["no-store"]
    assert Enum.sort(Map.keys(link)) == Enum.sort(@link_fields)

    replayed = create_link(token, attrs, key)
    assert json_response(replayed, 200)["data"] == link
    assert get_resp_header(replayed, "idempotency-status") == ["replayed"]

    assert build_conn()
           |> authenticated(token)
           |> get(~p"/api/v1/communication-links/#{link["id"]}")
           |> json_response(200)
           |> Map.fetch!("data") == link

    CommunicationsContractDouble.revoke(scope)
    denied_replay = create_link(token, attrs, key)
    assert json_response(denied_replay, 403)["error"]["code"] == "communications_denied"

    denied_read =
      build_conn()
      |> authenticated(token)
      |> get(~p"/api/v1/communication-links/#{link["id"]}")

    assert json_response(denied_read, 403)["error"]["code"] == "communications_denied"
  end

  test "records one bounded handoff and keeps external delivery unverified", %{
    token: token,
    context: context
  } do
    link = authorized_link(token, context)
    key = Ecto.UUID.generate()
    attrs = delivery_attrs(link)
    response = request_delivery(token, link, attrs, key)
    receipt = json_response(response, 201)["data"]

    assert receipt["status"] == "succeeded"
    assert receipt["contract_acceptance"] == "contract_accepted"
    assert receipt["external_delivery_state"] == "unverified"
    assert receipt["communication_link_id"] == link["id"]
    assert Enum.sort(Map.keys(receipt)) == Enum.sort(@receipt_fields)
    assert byte_size(response.resp_body) < 4_096
    assert get_resp_header(response, "cache-control") == ["no-store"]

    replayed = request_delivery(token, link, attrs, key)
    assert json_response(replayed, 200)["data"] == receipt
    assert get_resp_header(replayed, "idempotency-status") == ["replayed"]
    assert map_size(CommunicationsContractDouble.deliveries()) == 1
  end

  test "recovers a lost response by reconciling the exact existing external handoff", %{
    token: token,
    context: context
  } do
    link = authorized_link(token, context)
    CommunicationsContractDouble.mode(:deliver, :lost_response)

    pending =
      request_delivery(token, link, delivery_attrs(link), Ecto.UUID.generate())
      |> json_response(201)
      |> Map.fetch!("data")

    assert pending["status"] == "attempted"
    assert pending["contract_acceptance"] == "pending"
    assert pending["external_delivery_state"] == "unverified"

    response =
      build_conn()
      |> authenticated(token, Ecto.UUID.generate())
      |> post(
        ~p"/api/v1/communication-links/#{link["id"]}/deliveries/#{pending["id"]}/reconcile",
        %{"expected_version" => pending["lock_version"]}
      )

    recovered = json_response(response, 200)["data"]
    assert recovered["id"] == pending["id"]
    assert recovered["status"] == "succeeded"
    assert recovered["contract_acceptance"] == "contract_accepted"
    assert recovered["external_delivery_state"] == "unverified"
    assert map_size(CommunicationsContractDouble.deliveries()) == 1
  end

  test "rejects raw content, caller outcomes, and missing versions", %{
    token: token,
    context: context
  } do
    attrs = link_attrs(context)
    grant(context, attrs)

    response =
      create_link(
        token,
        Map.put(attrs, "message", "private message content"),
        Ecto.UUID.generate()
      )

    assert json_response(response, 422)["error"]["code"] == "validation_failed"
    refute response.resp_body =~ "private message content"

    link =
      create_link(token, attrs, Ecto.UUID.generate()) |> json_response(201) |> Map.fetch!("data")

    delivery =
      request_delivery(
        token,
        link,
        Map.put(delivery_attrs(link), "response_body", "private external response"),
        Ecto.UUID.generate()
      )

    assert json_response(delivery, 422)["error"]["code"] == "validation_failed"
    refute delivery.resp_body =~ "private external response"
    assert CommunicationsContractDouble.deliveries() == %{}

    invalid_version =
      request_delivery(
        token,
        link,
        Map.delete(delivery_attrs(link), "expected_version"),
        Ecto.UUID.generate()
      )

    assert json_response(invalid_version, 400)["error"]["code"] == "invalid_request"

    receipt_id = Ecto.UUID.generate()

    for field <- ~w(status response_body external_reference provider reason) do
      rejected =
        build_conn()
        |> authenticated(token, Ecto.UUID.generate())
        |> post(
          ~p"/api/v1/communication-links/#{link["id"]}/deliveries/#{receipt_id}/reconcile",
          %{"expected_version" => 1, field => "untrusted outcome"}
        )

      assert json_response(rejected, 400)["error"]["code"] == "invalid_request"
      refute rejected.resp_body =~ "untrusted outcome"
    end
  end

  defp authorized_link(token, context) do
    attrs = link_attrs(context)
    grant(context, attrs)
    create_link(token, attrs, Ecto.UUID.generate()) |> json_response(201) |> Map.fetch!("data")
  end

  defp link_attrs(context) do
    party = PartyOnboardingFixtures.create_party(context)

    %{
      "subject_type" => "party",
      "subject_id" => party["id"],
      "subject_version" => party["lock_version"],
      "conversation_id" => Ecto.UUID.generate(),
      "reason" => "Link the authorized party conversation"
    }
  end

  defp grant(context, attrs) do
    scope = %{
      tenant_id: context.tenant_id,
      actor_id: context.actor_id,
      conversation_id: attrs["conversation_id"]
    }

    CommunicationsContractDouble.grant(scope)
    scope
  end

  defp delivery_attrs(link) do
    %{
      "expected_version" => link["lock_version"],
      "delivery_key" => Ecto.UUID.generate(),
      "reason" => "Qualify the authorized contract handoff"
    }
  end

  defp create_link(token, attrs, key) do
    build_conn()
    |> authenticated(token, key)
    |> post(~p"/api/v1/communication-links", attrs)
  end

  defp request_delivery(token, link, attrs, key) do
    build_conn()
    |> authenticated(token, key)
    |> post(~p"/api/v1/communication-links/#{link["id"]}/deliveries", attrs)
  end

  defp sign_in do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> post(~p"/api/v1/session", %{"access_code" => @access_code})
    |> json_response(201)
    |> get_in(["data", "access_token"])
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

  defp authenticated(conn, token, key \\ nil) do
    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("accept", "application/json")

    if key, do: put_req_header(conn, "idempotency-key", key), else: conn
  end
end
