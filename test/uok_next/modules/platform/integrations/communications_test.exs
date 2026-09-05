defmodule UokNext.Modules.Platform.Integrations.CommunicationsTest do
  use UokNext.DataCase, async: false

  alias UokNext.CommunicationsContractDouble, as: Double
  alias UokNext.Kernel.{AuditEvent, CommandReceipt, OutboxEvent, TenantTransaction}
  alias UokNext.Modules.Master.Parties.Public, as: Parties

  alias UokNext.Modules.Platform.Integrations.Infrastructure.{
    CommunicationLinkRecord,
    ConnectorReceiptRecord
  }

  alias UokNext.Modules.Platform.Integrations.Public
  alias UokNext.PartyOnboardingFixtures, as: Fixtures

  @permissions ~w(parties:create parties:read parties:evidence:submit evidence:read communications:link communications:read communications:deliver communications:reconcile integrations:attempt integrations:read integrations:reconcile)

  setup do
    previous = Application.get_env(:uok_next, :communications_adapter)
    Application.put_env(:uok_next, :communications_adapter, Double)
    on_exit(fn -> Application.put_env(:uok_next, :communications_adapter, previous) end)
    start_supervised!(Double)
    context = Fixtures.context(%{permissions: @permissions})
    party = Fixtures.create_party(context)
    conversation_id = Ecto.UUID.generate()

    scope = %{
      tenant_id: context.tenant_id,
      actor_id: context.actor_id,
      conversation_id: conversation_id
    }

    Double.grant(scope)

    attrs = %{
      "subject_type" => "party",
      "subject_id" => party["id"],
      "subject_version" => party["lock_version"],
      "conversation_id" => conversation_id,
      "reason" => "Qualify independently authorized conversation link"
    }

    %{context: context, party: party, scope: scope, attrs: attrs}
  end

  test "persists one immutable link with atomic evidence and independently authorizes replay",
       state do
    key = Ecto.UUID.generate()
    assert {:ok, link, :executed} = Public.link_communication(state.attrs, state.context, key)
    assert {:ok, ^link, :replayed} = Public.link_communication(state.attrs, state.context, key)
    assert {:ok, ^link} = Public.get_communication_link(link["id"], state.context)
    assert count(CommunicationLinkRecord, state.context) == 1
    assert count(CommandReceipt, state.context) == 2
    assert count(AuditEvent, state.context) == 2
    assert count(OutboxEvent, state.context) == 2
    assert link["external_delivery_state"] == "unverified"
    Double.revoke(state.scope)

    assert {:error, %{code: "communications_denied"}} =
             Public.link_communication(state.attrs, state.context, key)

    assert {:error, %{code: "communications_denied"}} =
             Public.get_communication_link(link["id"], state.context)
  end

  test "checks current party permission and exact version before link or delivery replay",
       state do
    key = Ecto.UUID.generate()
    {:ok, link, :executed} = Public.link_communication(state.attrs, state.context, key)

    denied = %{
      state.context
      | permissions: MapSet.delete(state.context.permissions, "parties:read")
    }

    assert {:error, %{code: "forbidden"}} = Public.link_communication(state.attrs, denied, key)

    assert {:error, %{code: "forbidden"}} =
             Public.request_communication_delivery(
               link["id"],
               delivery(),
               1,
               denied,
               Ecto.UUID.generate()
             )

    evidence = Fixtures.persisted_evidence_attrs(state.context, state.party)

    assert {:ok, _, :executed} =
             Parties.submit_evidence(
               state.party["id"],
               evidence,
               1,
               state.context,
               Ecto.UUID.generate()
             )

    assert {:error, %{code: "stale_state"}} =
             Public.link_communication(state.attrs, state.context, key)

    assert {:error, %{code: "stale_state"}} =
             Public.get_communication_link(link["id"], state.context)

    assert {:error, %{code: "stale_state"}} =
             Public.request_communication_delivery(
               link["id"],
               delivery(),
               1,
               state.context,
               Ecto.UUID.generate()
             )

    assert map_size(Double.deliveries()) == 0
  end

  test "durably records attempt then accepts content-free contract exactly once", state do
    link = link(state)
    key = Ecto.UUID.generate()
    attrs = delivery()

    assert {:ok, receipt, :executed} =
             Public.request_communication_delivery(link["id"], attrs, 1, state.context, key)

    assert receipt["status"] == "succeeded"
    assert receipt["contract_acceptance"] == "contract_accepted"
    assert receipt["external_delivery_state"] == "unverified"

    assert {:ok, ^receipt, :replayed} =
             Public.request_communication_delivery(link["id"], attrs, 1, state.context, key)

    assert count(ConnectorReceiptRecord, state.context) == 1
    assert map_size(Double.deliveries()) == 1
    assert Double.calls()[:deliver] == 1

    assert {:error, %{code: "idempotency_conflict"}} =
             Public.request_communication_delivery(
               link["id"],
               Map.put(attrs, "delivery_key", Ecto.UUID.generate()),
               1,
               state.context,
               key
             )

    Double.revoke(state.scope)

    assert {:error, %{code: "communications_denied"}} =
             Public.request_communication_delivery(link["id"], attrs, 1, state.context, key)
  end

  test "lost acknowledgement reconciles without duplicate handoff and with idempotent recovery",
       state do
    link = link(state)
    Double.mode(:deliver, :lost_response)

    {:ok, receipt, :executed} =
      Public.request_communication_delivery(
        link["id"],
        delivery(),
        1,
        state.context,
        Ecto.UUID.generate()
      )

    assert receipt["status"] == "attempted"
    assert receipt["contract_acceptance"] == "pending"
    assert map_size(Double.deliveries()) == 1
    key = Ecto.UUID.generate()

    assert {:ok, recovered, :executed} =
             Public.reconcile_communication_delivery(
               link["id"],
               receipt["id"],
               1,
               state.context,
               key
             )

    assert recovered["status"] == "succeeded"

    assert {:ok, ^recovered, :replayed} =
             Public.reconcile_communication_delivery(
               link["id"],
               receipt["id"],
               1,
               state.context,
               key
             )

    assert map_size(Double.deliveries()) == 1
    Double.revoke(state.scope)

    assert {:error, %{code: "communications_denied"}} =
             Public.reconcile_communication_delivery(
               link["id"],
               receipt["id"],
               1,
               state.context,
               key
             )
  end

  test "malformed or substituted acknowledgement cannot manufacture success", state do
    link = link(state)

    for mode <- [:malformed, :substitution] do
      Double.mode(:deliver, mode)

      {:ok, receipt, :executed} =
        Public.request_communication_delivery(
          link["id"],
          delivery(),
          1,
          state.context,
          Ecto.UUID.generate()
        )

      assert receipt["status"] == "attempted"
      assert receipt["response_sha256"] == nil
      assert receipt["external_reference"] == nil
      Double.mode(:reconcile, mode)

      assert {:error, %{code: "communications_invalid_response"}} =
               Public.reconcile_communication_delivery(
                 link["id"],
                 receipt["id"],
                 1,
                 state.context,
                 Ecto.UUID.generate()
               )
    end

    assert map_size(Double.deliveries()) == 0
  end

  test "server timeout permits only an exact retry lineage", state do
    link = link(state)
    attrs = delivery()
    Double.mode(:deliver, :timed_out)

    {:ok, attempted, :executed} =
      Public.request_communication_delivery(
        link["id"],
        attrs,
        1,
        state.context,
        Ecto.UUID.generate()
      )

    retry_attrs = Map.put(attrs, "previous_receipt_id", attempted["id"])

    assert {:error, %{code: "validation_failed"}} =
             Public.request_communication_delivery(
               link["id"],
               retry_attrs,
               1,
               state.context,
               Ecto.UUID.generate()
             )

    expire(attempted["id"], state.context)

    assert {:ok, timed_out, :executed} =
             Public.reconcile_communication_delivery(
               link["id"],
               attempted["id"],
               1,
               state.context,
               Ecto.UUID.generate()
             )

    assert timed_out["status"] == "timed_out"
    Double.mode(:deliver, :available)

    assert {:ok, retry, :executed} =
             Public.request_communication_delivery(
               link["id"],
               retry_attrs,
               1,
               state.context,
               Ecto.UUID.generate()
             )

    assert retry["attempt_number"] == 2
    assert retry["status"] == "succeeded"
    assert retry["request_sha256"] == attempted["request_sha256"]

    assert {:error, %{code: "validation_failed"}} =
             Public.request_communication_delivery(
               link["id"],
               Map.put(attrs, "previous_receipt_id", retry["id"]),
               1,
               state.context,
               Ecto.UUID.generate()
             )

    assert map_size(Double.deliveries()) == 1
  end

  test "rejects stale versions, raw content and reserved generic receipt paths", state do
    link = link(state)

    assert {:error, %{code: "stale_state"}} =
             Public.request_communication_delivery(
               link["id"],
               delivery(),
               2,
               state.context,
               Ecto.UUID.generate()
             )

    assert {:error, %{code: "validation_failed"}} =
             Public.request_communication_delivery(
               link["id"],
               Map.put(delivery(), "body", "private message"),
               1,
               state.context,
               Ecto.UUID.generate()
             )

    {:ok, receipt, :executed} =
      Public.request_communication_delivery(
        link["id"],
        delivery(),
        1,
        state.context,
        Ecto.UUID.generate()
      )

    assert {:error, %{code: "forbidden"}} = Public.get(receipt["id"], state.context)

    assert {:error, %{code: "forbidden"}} =
             Public.reconcile(
               receipt["id"],
               2,
               %{"status" => "succeeded"},
               state.context,
               Ecto.UUID.generate()
             )

    attrs =
      receipt
      |> Map.take(
        ~w(connector_role operation delivery_key request_sha256 subject_type subject_id subject_version)
      )
      |> Map.merge(%{
        "timeout_ms" => 30_000,
        "reason" => "Caller cannot forge contract acceptance"
      })

    assert {:error, %{code: "forbidden"}} =
             Public.begin_attempt(attrs, state.context, Ecto.UUID.generate())
  end

  test "foreign tenant links and receipts remain hidden under forced row security", state do
    link = link(state)

    {:ok, receipt, :executed} =
      Public.request_communication_delivery(
        link["id"],
        delivery(),
        1,
        state.context,
        Ecto.UUID.generate()
      )

    other = Fixtures.context(%{permissions: @permissions})
    assert {:error, %{code: "not_found"}} = Public.get_communication_link(link["id"], other)

    assert {:error, %{code: "not_found"}} =
             Public.reconcile_communication_delivery(
               link["id"],
               receipt["id"],
               1,
               other,
               Ecto.UUID.generate()
             )

    Repo.query!("SET LOCAL ROLE pg_read_all_data", [], log: false)
    Repo.query!("SELECT set_config('uok.tenant_id', '', true)", [], log: false)
    assert Repo.aggregate(CommunicationLinkRecord, :count) == 0
    assert count(CommunicationLinkRecord, other) == 0
    assert count(CommunicationLinkRecord, state.context) == 1
  end

  test "rejects an outer transaction before authorizing or opening transport", state do
    link = link(state)
    calls = Double.calls()

    assert {:error, %{code: "transaction_not_supported"}} =
             TenantTransaction.run(state.context, fn ->
               Public.request_communication_delivery(
                 link["id"],
                 delivery(),
                 1,
                 state.context,
                 Ecto.UUID.generate()
               )
             end)

    assert Double.calls() == calls
    assert count(ConnectorReceiptRecord, state.context) == 0
  end

  test "concurrent requests preserve one durable attempt and one external handoff", state do
    link = link(state)
    key = Ecto.UUID.generate()
    attrs = delivery()

    results =
      1..2
      |> Task.async_stream(
        fn _ ->
          Public.request_communication_delivery(link["id"], attrs, 1, state.context, key)
        end,
        max_concurrency: 2,
        timeout: 10_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.sort(Enum.map(results, fn {:ok, _receipt, disposition} -> disposition end)) ==
             [:executed, :replayed]

    assert count(ConnectorReceiptRecord, state.context) == 1
    assert map_size(Double.deliveries()) == 1
    assert Double.calls()[:deliver] == 1
  end

  test "row security rejects a cross-tenant link insert even with table write privileges",
       state do
    _link = link(state)
    Repo.query!("SET LOCAL ROLE pg_write_all_data", [], log: false)

    Repo.query!("SELECT set_config('uok.tenant_id', $1, true)", [state.context.tenant_id],
      log: false
    )

    attrs = %{
      id: Ecto.UUID.generate(),
      tenant_id: Ecto.UUID.generate(),
      subject_type: "party",
      subject_id: state.party["id"],
      subject_version: 1,
      conversation_id: state.scope.conversation_id,
      created_by_actor_id: state.context.actor_id,
      lock_version: 1,
      inserted_at: DateTime.utc_now()
    }

    assert_raise Postgrex.Error, ~r/row-level security policy/, fn ->
      Repo.insert_all(CommunicationLinkRecord, [attrs])
    end
  end

  test "health is permission bound and default-disabled without affecting party access", state do
    assert {:ok, %{"status" => "local_contract_double"}} =
             Public.communications_health(state.context)

    Application.put_env(:uok_next, :communications_adapter, :disabled)
    assert {:ok, %{"status" => "unavailable"}} = Public.communications_health(state.context)
    assert {:ok, _party} = Parties.get(state.party["id"], state.context)

    assert {:error, %{code: "communications_unavailable"}} =
             Public.link_communication(state.attrs, state.context, Ecto.UUID.generate())

    denied = %{state.context | permissions: MapSet.new()}
    assert {:error, %{code: "forbidden"}} = Public.communications_health(denied)
  end

  defp link(state) do
    {:ok, link, :executed} =
      Public.link_communication(state.attrs, state.context, Ecto.UUID.generate())

    link
  end

  defp delivery,
    do: %{
      "delivery_key" => Ecto.UUID.generate(),
      "reason" => "Qualify a content-free delivery intent"
    }

  defp count(schema, context) do
    TenantTransaction.run(context, fn ->
      Repo.aggregate(
        from(record in schema, where: record.tenant_id == ^context.tenant_id),
        :count
      )
    end)
  end

  defp expire(id, context) do
    TenantTransaction.run(context, fn ->
      Repo.update_all(from(receipt in ConnectorReceiptRecord, where: receipt.id == ^id),
        set: [deadline_at: DateTime.add(DateTime.utc_now(), -1)]
      )
    end)
  end
end
