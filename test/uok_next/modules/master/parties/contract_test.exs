defmodule UokNext.Modules.Master.Parties.ContractTest do
  use UokNext.DataCase, async: true

  import UokNext.PartyOnboardingFixtures

  alias UokNext.Kernel.{AuditEvent, CommandReceipt, OutboxEvent}
  alias UokNext.Modules.Master.Parties.Public
  alias UokNext.Modules.Platform.Workflow.Infrastructure.HumanTaskRecord

  test "the selected implementation preserves the complete command contract" do
    context = context()
    create_attrs = party_attrs()
    create_key = Ecto.UUID.generate()

    assert {:ok, party, :executed} = Public.create_draft(create_attrs, context, create_key)
    assert {:ok, ^party, :replayed} = Public.create_draft(create_attrs, context, create_key)

    assert {:ok, evidenced, :executed} =
             Public.submit_evidence(
               party["id"],
               persisted_evidence_attrs(context, party),
               party["lock_version"],
               context,
               Ecto.UUID.generate()
             )

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
    assert approved["review_task"]["status"] == "completed"
    assert approved["lock_version"] == 3
    assert Repo.aggregate(CommandReceipt, :count) == 3
    assert Repo.aggregate(AuditEvent, :count) == 5
    assert Repo.aggregate(OutboxEvent, :count) == 5
    assert Repo.aggregate(HumanTaskRecord, :count) == 1
  end

  test "the selected contract fails closed across authorization, tenancy, and concurrency" do
    owner_context = context()
    denied_context = context(%{permissions: []})

    assert {:error, denied} =
             Public.create_draft(party_attrs(), denied_context, Ecto.UUID.generate())

    assert denied.code == "forbidden"

    assert {:ok, party, :executed} =
             Public.create_draft(party_attrs(), owner_context, Ecto.UUID.generate())

    assert {:error, hidden} = Public.get(party["id"], context())
    assert hidden.code == "not_found"

    assert {:ok, evidenced, :executed} =
             Public.submit_evidence(
               party["id"],
               persisted_evidence_attrs(owner_context, party),
               party["lock_version"],
               owner_context,
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
               owner_context,
               Ecto.UUID.generate()
             )

    assert stale.code == "stale_state"
  end
end
