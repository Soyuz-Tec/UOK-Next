defmodule UokNext.Modules.Master.Parties.PublicTest do
  use UokNext.DataCase, async: true

  import UokNext.PartyOnboardingFixtures

  alias UokNext.Kernel.{AuditEvent, CommandReceipt, OutboxEvent, TenantTransaction}
  alias UokNext.Modules.Master.Parties.Infrastructure.PartyRecord
  alias UokNext.Modules.Master.Parties.Public

  describe "create_draft/3" do
    test "commits party state, receipt, audit, and outbox atomically" do
      context = context()

      assert {:ok, party, :executed} =
               Public.create_draft(party_attrs(), context, Ecto.UUID.generate())

      assert party["tenant_id"] == context.tenant_id
      assert party["country_code"] == "GH"
      assert party["status"] == "draft"
      assert party["lock_version"] == 1
      assert tenant_count(PartyRecord, context) == 1
      assert tenant_count(CommandReceipt, context) == 1
      assert tenant_count(AuditEvent, context) == 1
      assert tenant_count(OutboxEvent, context) == 1

      audit = tenant_one(AuditEvent, context)
      event = tenant_one(OutboxEvent, context)
      assert audit.actor_id == context.actor_id
      assert audit.correlation_id == context.correlation_id
      assert audit.action == "master.parties.create_draft"
      assert event.event_name == "master.parties.party_draft_created"
      assert event.status == "pending"
    end

    test "replays the completed response without duplicating state or evidence" do
      context = context()
      attrs = party_attrs()
      idempotency_key = Ecto.UUID.generate()

      assert {:ok, first, :executed} = Public.create_draft(attrs, context, idempotency_key)
      assert {:ok, second, :replayed} = Public.create_draft(attrs, context, idempotency_key)
      assert second == first
      assert tenant_count(PartyRecord, context) == 1
      assert tenant_count(CommandReceipt, context) == 1
      assert tenant_count(AuditEvent, context) == 1
      assert tenant_count(OutboxEvent, context) == 1
    end

    test "rejects reuse of an idempotency key for different input" do
      context = context()
      idempotency_key = Ecto.UUID.generate()

      assert {:ok, _party, :executed} =
               Public.create_draft(party_attrs(), context, idempotency_key)

      assert {:error, error} =
               Public.create_draft(
                 party_attrs(%{"stable_identifier" => "different-party"}),
                 context,
                 idempotency_key
               )

      assert error.code == "idempotency_conflict"
      assert tenant_count(PartyRecord, context) == 1
    end

    test "fails closed without permission or valid input" do
      denied_context = context(%{permissions: []})

      assert {:error, denied} =
               Public.create_draft(party_attrs(), denied_context, Ecto.UUID.generate())

      assert denied.code == "forbidden"

      assert {:error, invalid} =
               Public.create_draft(
                 party_attrs(%{"country_code" => "not-a-country"}),
                 context(),
                 Ecto.UUID.generate()
               )

      assert invalid.code == "validation_failed"
      assert tenant_count(PartyRecord, denied_context) == 0
      assert tenant_count(CommandReceipt, denied_context) == 0
    end

    test "enforces tenant-scoped stable identity" do
      tenant_id = Ecto.UUID.generate()
      stable_identifier = "shared-registration"

      assert {:ok, _party, :executed} =
               Public.create_draft(
                 party_attrs(%{"stable_identifier" => stable_identifier}),
                 context(%{tenant_id: tenant_id}),
                 Ecto.UUID.generate()
               )

      assert {:error, duplicate} =
               Public.create_draft(
                 party_attrs(%{"stable_identifier" => stable_identifier}),
                 context(%{tenant_id: tenant_id}),
                 Ecto.UUID.generate()
               )

      assert duplicate.code == "validation_failed"

      assert {:ok, _other_tenant_party, :executed} =
               Public.create_draft(
                 party_attrs(%{"stable_identifier" => stable_identifier}),
                 context(),
                 Ecto.UUID.generate()
               )
    end
  end

  describe "onboarding transitions" do
    test "submits evidence and approves through versioned named commands" do
      context = context()
      party = create_party(context)

      assert {:ok, evidenced, :executed} =
               Public.submit_evidence(
                 party["id"],
                 evidence_attrs(),
                 party["lock_version"],
                 context,
                 Ecto.UUID.generate()
               )

      assert evidenced["status"] == "evidence_submitted"
      assert evidenced["lock_version"] == 2

      assert {:ok, approved, :executed} =
               Public.decide(
                 party["id"],
                 %{"decision" => "approve", "reason" => "Evidence passed compliance review"},
                 evidenced["lock_version"],
                 context,
                 Ecto.UUID.generate()
               )

      assert approved["status"] == "approved"
      assert approved["lock_version"] == 3
      assert tenant_count(AuditEvent, context) == 3
      assert tenant_count(OutboxEvent, context) == 3
      assert tenant_count(CommandReceipt, context) == 3
    end

    test "rejects stale state and missing approval evidence" do
      context = context()
      party = create_party(context)

      assert {:error, missing_evidence} =
               Public.decide(
                 party["id"],
                 %{"decision" => "approve", "reason" => "Attempt approval without evidence"},
                 party["lock_version"],
                 context,
                 Ecto.UUID.generate()
               )

      assert missing_evidence.code == "validation_failed"

      assert {:ok, evidenced, :executed} =
               Public.submit_evidence(
                 party["id"],
                 evidence_attrs(),
                 party["lock_version"],
                 context,
                 Ecto.UUID.generate()
               )

      assert {:error, stale} =
               Public.decide(
                 party["id"],
                 %{"decision" => "hold", "reason" => "Review requires clarification"},
                 party["lock_version"],
                 context,
                 Ecto.UUID.generate()
               )

      assert stale.code == "stale_state"
      assert evidenced["status"] == "evidence_submitted"
    end

    test "tenant mismatch is indistinguishable from an unknown record" do
      owner_context = context()
      other_context = context()
      party = create_party(owner_context)

      assert {:error, hidden} = Public.get(party["id"], other_context)
      assert hidden.code == "not_found"

      assert {:error, hidden} =
               Public.submit_evidence(
                 party["id"],
                 evidence_attrs(),
                 party["lock_version"],
                 other_context,
                 Ecto.UUID.generate()
               )

      assert hidden.code == "not_found"
    end

    test "database row-level security rejects an unset or different tenant" do
      owner_context = context()
      other_context = context()
      _party = create_party(owner_context)

      Repo.query!("SET LOCAL ROLE pg_read_all_data", [], log: false)
      Repo.query!("SELECT set_config('uok.tenant_id', '', true)", [], log: false)
      assert Repo.aggregate(PartyRecord, :count) == 0
      assert tenant_count(PartyRecord, other_context) == 0
      assert tenant_count(PartyRecord, owner_context) == 1
    end

    test "denies each consequential action without its named permission" do
      owner_context = context()
      party = create_party(owner_context)

      evidence_context =
        context(%{
          tenant_id: owner_context.tenant_id,
          permissions: ["parties:read"]
        })

      assert {:error, denied} =
               Public.submit_evidence(
                 party["id"],
                 evidence_attrs(),
                 party["lock_version"],
                 evidence_context,
                 Ecto.UUID.generate()
               )

      assert denied.code == "forbidden"
    end
  end

  defp tenant_count(schema, context) do
    TenantTransaction.run(context, fn -> Repo.aggregate(schema, :count) end)
  end

  defp tenant_one(schema, context) do
    TenantTransaction.run(context, fn -> Repo.one!(schema) end)
  end
end
