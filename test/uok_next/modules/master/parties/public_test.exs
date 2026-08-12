defmodule UokNext.Modules.Master.Parties.PublicTest do
  use UokNext.DataCase, async: true

  import UokNext.PartyOnboardingFixtures

  alias UokNext.Kernel.{AuditEvent, CommandReceipt, OutboxEvent, TenantTransaction}
  alias UokNext.Modules.Master.Parties.Infrastructure.PartyRecord
  alias UokNext.Modules.Master.Parties.Public
  alias UokNext.Modules.Platform.Workflow.Infrastructure.HumanTaskRecord

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
    test "preflights permission, tenant visibility, state, and version before evidence storage" do
      owner_context = context()
      party = create_party(owner_context)

      assert :ok =
               Public.preflight_evidence(
                 party["id"],
                 party["lock_version"],
                 owner_context
               )

      assert {:error, stale} =
               Public.preflight_evidence(
                 party["id"],
                 party["lock_version"] + 1,
                 owner_context
               )

      assert stale.code == "stale_state"

      assert {:error, hidden} =
               Public.preflight_evidence(
                 party["id"],
                 party["lock_version"],
                 context()
               )

      assert hidden.code == "not_found"

      denied_context =
        context(%{tenant_id: owner_context.tenant_id, permissions: ["parties:read"]})

      assert {:error, denied} =
               Public.preflight_evidence(
                 party["id"],
                 party["lock_version"],
                 denied_context
               )

      assert denied.code == "forbidden"
    end

    test "submits evidence and approves through versioned named commands" do
      context = context()
      party = create_party(context)

      assert {:ok, evidenced, :executed} =
               Public.submit_evidence(
                 party["id"],
                 persisted_evidence_attrs(context, party),
                 party["lock_version"],
                 context,
                 Ecto.UUID.generate()
               )

      assert evidenced["status"] == "evidence_submitted"
      assert evidenced["lock_version"] == 2
      assert evidenced["review_task"]["status"] == "open"

      assert {:ok, approved, :executed} =
               Public.decide(
                 party["id"],
                 %{
                   "decision" => "approve",
                   "reason" => "Evidence passed compliance review",
                   "task_id" => evidenced["review_task"]["id"]
                 },
                 evidenced["lock_version"],
                 context,
                 Ecto.UUID.generate()
               )

      assert approved["status"] == "approved"
      assert approved["lock_version"] == 3
      assert approved["review_task"]["status"] == "completed"
      assert approved["review_task"]["resolution"] == "approve"
      assert tenant_count(HumanTaskRecord, context) == 1
      assert tenant_count(AuditEvent, context) == 5
      assert tenant_count(OutboxEvent, context) == 5
      assert tenant_count(CommandReceipt, context) == 3
    end

    test "rejects stale state and missing approval evidence" do
      context = context()
      party = create_party(context)

      assert {:error, missing_evidence} =
               Public.decide(
                 party["id"],
                 %{
                   "decision" => "approve",
                   "reason" => "Attempt approval without evidence",
                   "task_id" => Ecto.UUID.generate()
                 },
                 party["lock_version"],
                 context,
                 Ecto.UUID.generate()
               )

      assert missing_evidence.code == "validation_failed"

      assert {:ok, evidenced, :executed} =
               Public.submit_evidence(
                 party["id"],
                 persisted_evidence_attrs(context, party),
                 party["lock_version"],
                 context,
                 Ecto.UUID.generate()
               )

      assert {:error, stale} =
               Public.decide(
                 party["id"],
                 %{
                   "decision" => "hold",
                   "reason" => "Review requires clarification",
                   "task_id" => evidenced["review_task"]["id"]
                 },
                 party["lock_version"],
                 context,
                 Ecto.UUID.generate()
               )

      assert stale.code == "stale_state"
      assert evidenced["status"] == "evidence_submitted"
      assert tenant_one(HumanTaskRecord, context).status == "open"
    end

    test "rejects a task for a different subject and rolls back the command receipt" do
      context = context()
      first_party = create_party(context)
      second_party = create_party(context)

      assert {:ok, first, :executed} =
               Public.submit_evidence(
                 first_party["id"],
                 persisted_evidence_attrs(context, first_party),
                 first_party["lock_version"],
                 context,
                 Ecto.UUID.generate()
               )

      assert {:ok, second, :executed} =
               Public.submit_evidence(
                 second_party["id"],
                 persisted_evidence_attrs(context, second_party),
                 second_party["lock_version"],
                 context,
                 Ecto.UUID.generate()
               )

      receipts_before = tenant_count(CommandReceipt, context)

      assert {:error, mismatch} =
               Public.decide(
                 second_party["id"],
                 %{
                   "decision" => "approve",
                   "reason" => "Attempt to substitute another review task",
                   "task_id" => first["review_task"]["id"]
                 },
                 second["lock_version"],
                 context,
                 Ecto.UUID.generate()
               )

      assert mismatch.code == "validation_failed"
      assert tenant_count(CommandReceipt, context) == receipts_before
      assert tenant_count(HumanTaskRecord, context) == 2
      assert Enum.all?(tenant_all(HumanTaskRecord, context), &(&1.status == "open"))
    end

    test "replays the completed decision but rejects consumed-task reuse as a new command" do
      context = context()
      party = create_party(context)

      assert {:ok, evidenced, :executed} =
               Public.submit_evidence(
                 party["id"],
                 persisted_evidence_attrs(context, party),
                 party["lock_version"],
                 context,
                 Ecto.UUID.generate()
               )

      decision = %{
        "decision" => "approve",
        "reason" => "Evidence passed compliance review",
        "task_id" => evidenced["review_task"]["id"]
      }

      decision_key = Ecto.UUID.generate()

      assert {:ok, approved, :executed} =
               Public.decide(
                 party["id"],
                 decision,
                 evidenced["lock_version"],
                 context,
                 decision_key
               )

      counts = evidence_counts(context)

      assert {:ok, ^approved, :replayed} =
               Public.decide(
                 party["id"],
                 decision,
                 evidenced["lock_version"],
                 context,
                 decision_key
               )

      assert evidence_counts(context) == counts

      assert {:error, consumed} =
               Public.decide(
                 party["id"],
                 decision,
                 approved["lock_version"],
                 context,
                 Ecto.UUID.generate()
               )

      assert consumed.code == "validation_failed"
      assert evidence_counts(context) == counts
      assert tenant_one(HumanTaskRecord, context).status == "completed"
    end

    test "tenant mismatch hides the review task and preserves both records" do
      owner_context = context()
      other_context = context(%{tenant_id: owner_context.tenant_id})
      foreign_context = context()
      party = create_party(owner_context)

      assert {:ok, evidenced, :executed} =
               Public.submit_evidence(
                 party["id"],
                 persisted_evidence_attrs(owner_context, party),
                 party["lock_version"],
                 owner_context,
                 Ecto.UUID.generate()
               )

      foreign_party = create_party(foreign_context)

      assert {:ok, foreign_evidenced, :executed} =
               Public.submit_evidence(
                 foreign_party["id"],
                 persisted_evidence_attrs(foreign_context, foreign_party),
                 foreign_party["lock_version"],
                 foreign_context,
                 Ecto.UUID.generate()
               )

      assert {:error, hidden} =
               Public.decide(
                 party["id"],
                 %{
                   "decision" => "approve",
                   "reason" => "Attempt cross-tenant task substitution",
                   "task_id" => foreign_evidenced["review_task"]["id"]
                 },
                 evidenced["lock_version"],
                 other_context,
                 Ecto.UUID.generate()
               )

      assert hidden.code == "not_found"
      assert tenant_one(HumanTaskRecord, owner_context).status == "open"
      assert tenant_one(HumanTaskRecord, foreign_context).status == "open"
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
                 persisted_evidence_attrs(owner_context, party),
                 party["lock_version"],
                 other_context,
                 Ecto.UUID.generate()
               )

      assert hidden.code == "not_found"
    end

    test "database row-level security rejects an unset or different tenant" do
      owner_context = context()
      other_context = context()
      party = create_party(owner_context)

      assert {:ok, _evidenced, :executed} =
               Public.submit_evidence(
                 party["id"],
                 persisted_evidence_attrs(owner_context, party),
                 party["lock_version"],
                 owner_context,
                 Ecto.UUID.generate()
               )

      Repo.query!("SET LOCAL ROLE pg_read_all_data", [], log: false)
      Repo.query!("SELECT set_config('uok.tenant_id', '', true)", [], log: false)
      assert Repo.aggregate(PartyRecord, :count) == 0
      assert Repo.aggregate(HumanTaskRecord, :count) == 0
      assert tenant_count(PartyRecord, other_context) == 0
      assert tenant_count(HumanTaskRecord, other_context) == 0
      assert tenant_count(PartyRecord, owner_context) == 1
      assert tenant_count(HumanTaskRecord, owner_context) == 1
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
                 persisted_evidence_attrs(owner_context, party),
                 party["lock_version"],
                 evidence_context,
                 Ecto.UUID.generate()
               )

      assert denied.code == "forbidden"

      assert {:ok, evidenced, :executed} =
               Public.submit_evidence(
                 party["id"],
                 persisted_evidence_attrs(owner_context, party),
                 party["lock_version"],
                 owner_context,
                 Ecto.UUID.generate()
               )

      assert {:error, decision_denied} =
               Public.decide(
                 party["id"],
                 %{
                   "decision" => "approve",
                   "reason" => "Attempt decision without approval authority",
                   "task_id" => evidenced["review_task"]["id"]
                 },
                 evidenced["lock_version"],
                 evidence_context,
                 Ecto.UUID.generate()
               )

      assert decision_denied.code == "forbidden"
      assert tenant_one(HumanTaskRecord, owner_context).status == "open"
    end
  end

  defp tenant_count(schema, context) do
    TenantTransaction.run(context, fn ->
      Repo.aggregate(
        from(record in schema, where: record.tenant_id == ^context.tenant_id),
        :count
      )
    end)
  end

  defp tenant_one(schema, context) do
    TenantTransaction.run(context, fn ->
      Repo.one!(from record in schema, where: record.tenant_id == ^context.tenant_id)
    end)
  end

  defp tenant_all(schema, context) do
    TenantTransaction.run(context, fn ->
      Repo.all(from record in schema, where: record.tenant_id == ^context.tenant_id)
    end)
  end

  defp evidence_counts(context) do
    %{
      receipts: tenant_count(CommandReceipt, context),
      audits: tenant_count(AuditEvent, context),
      events: tenant_count(OutboxEvent, context),
      tasks: tenant_count(HumanTaskRecord, context)
    }
  end
end
