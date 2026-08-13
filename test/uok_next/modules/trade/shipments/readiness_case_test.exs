defmodule UokNext.Modules.Trade.Shipments.ReadinessCaseTest do
  use UokNext.DataCase, async: true

  import Ecto.Query

  alias UokNext.Kernel.{AuditEvent, OutboxEvent, TenantTransaction}
  alias UokNext.Modules.Platform.Integrations.Infrastructure.ConnectorReceiptRecord
  alias UokNext.Modules.Trade.Contracts.Infrastructure.PurchaseCommitmentProposalRecord
  alias UokNext.Modules.Trade.Shipments.Infrastructure.ShipmentReadinessCaseRecord
  alias UokNext.Modules.Trade.Shipments.Public, as: Shipments
  alias UokNext.ProcurementFixtures
  alias UokNext.Repo

  @effect_flags ~w(shipment_created dispatch_created inventory_effect_created finance_effect_created external_effect_created)

  test "creates one source-derived readiness case and records exact GO without execution" do
    context = ProcurementFixtures.context()
    source = ProcurementFixtures.approved_proposal(context)
    key = Ecto.UUID.generate()
    attrs = readiness_attrs(source.proposal)

    assert {:ok, readiness, :executed} =
             Shipments.create_readiness_case(
               attrs,
               source.proposal["lock_version"],
               context,
               key
             )

    assert {:ok, ^readiness, :replayed} =
             Shipments.create_readiness_case(
               attrs,
               source.proposal["lock_version"],
               context,
               key
             )

    assert readiness["status"] == "draft"

    assert Decimal.equal?(
             Decimal.new(readiness["source_snapshot"]["commercial_source"]["total_price"]),
             Decimal.new("2250")
           )

    assert checklist_status(readiness, "verified_operational_readiness_evidence") == "pending"
    assert_no_effects(readiness)

    evidence_id =
      ProcurementFixtures.persisted_evidence(
        context,
        "shipment_readiness_case",
        readiness["id"],
        "shipment readiness bundle"
      )

    assert {:ok, submitted, :executed} =
             Shipments.submit_readiness_evidence(
               readiness["id"],
               %{"evidence_id" => evidence_id, "reason" => "Attach readiness evidence bundle"},
               readiness["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert submitted["status"] == "awaiting_review"
    assert submitted["review_task"]["subject_version"] == submitted["lock_version"]
    assert checklist_status(submitted, "verified_operational_readiness_evidence") == "passed"

    decision = %{
      "decision" => "go",
      "reason" => "Record exact shipment-readiness GO",
      "task_id" => submitted["review_task"]["id"]
    }

    decision_key = Ecto.UUID.generate()

    assert {:ok, ready, :executed} =
             Shipments.decide_readiness(
               submitted["id"],
               decision,
               submitted["lock_version"],
               context,
               decision_key
             )

    assert {:ok, ^ready, :replayed} =
             Shipments.decide_readiness(
               submitted["id"],
               decision,
               submitted["lock_version"],
               context,
               decision_key
             )

    assert ready["status"] == "go"
    assert ready["review_task"]["resolution"] == "approve"
    assert_no_effects(ready)
    assert count(ShipmentReadinessCaseRecord, context) == 1
    assert count(ConnectorReceiptRecord, context) == 0
    assert_effect_flags(AuditEvent, :metadata, :resource_id, ready["id"], context)
    assert_effect_flags(OutboxEvent, :payload, :aggregate_id, ready["id"], context)
  end

  test "fails closed for permission, tenant, version, duplicate, and client checklist injection" do
    context = ProcurementFixtures.context()
    source = ProcurementFixtures.approved_proposal(context)

    injected = readiness_attrs(source.proposal) |> Map.put("checklist_snapshot", %{})

    assert {:error, invalid} =
             Shipments.create_readiness_case(
               injected,
               source.proposal["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert invalid.code == "validation_failed"

    assert {:error, stale} =
             Shipments.create_readiness_case(
               readiness_attrs(source.proposal),
               source.proposal["lock_version"] + 1,
               context,
               Ecto.UUID.generate()
             )

    assert stale.code == "stale_state"

    foreign = ProcurementFixtures.context()

    assert {:error, hidden} =
             Shipments.create_readiness_case(
               readiness_attrs(source.proposal),
               source.proposal["lock_version"],
               foreign,
               Ecto.UUID.generate()
             )

    assert hidden.code == "not_found"

    denied = ProcurementFixtures.context(%{tenant_id: context.tenant_id, permissions: []})

    assert {:error, forbidden} =
             Shipments.create_readiness_case(
               readiness_attrs(source.proposal),
               source.proposal["lock_version"],
               denied,
               Ecto.UUID.generate()
             )

    assert forbidden.code == "forbidden"

    assert {:ok, _created, :executed} =
             Shipments.create_readiness_case(
               readiness_attrs(source.proposal),
               source.proposal["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert {:error, duplicate} =
             Shipments.create_readiness_case(
               readiness_attrs(source.proposal, "duplicate-readiness"),
               source.proposal["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert duplicate.code == "validation_failed"
    assert count(ShipmentReadinessCaseRecord, context) == 1
  end

  test "rejects evidence and task substitution and recovers HOLD through fresh evidence" do
    context = ProcurementFixtures.context()
    source = ProcurementFixtures.approved_proposal(context)

    {:ok, readiness, :executed} =
      Shipments.create_readiness_case(
        readiness_attrs(source.proposal),
        source.proposal["lock_version"],
        context,
        Ecto.UUID.generate()
      )

    wrong_evidence =
      ProcurementFixtures.persisted_evidence(
        context,
        "purchase_commitment_proposal",
        source.proposal["id"],
        "wrong readiness subject"
      )

    assert {:error, hidden_evidence} =
             Shipments.submit_readiness_evidence(
               readiness["id"],
               %{"evidence_id" => wrong_evidence, "reason" => "Attempt evidence substitution"},
               readiness["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert hidden_evidence.code == "not_found"
    submitted = submit_evidence(readiness, context, "first readiness bundle")

    assert {:error, wrong_task} =
             Shipments.decide_readiness(
               submitted["id"],
               %{
                 "decision" => "go",
                 "reason" => "Attempt task substitution",
                 "task_id" => Ecto.UUID.generate()
               },
               submitted["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert wrong_task.code == "not_found"

    assert {:ok, held, :executed} =
             Shipments.decide_readiness(
               submitted["id"],
               %{
                 "decision" => "hold",
                 "reason" => "Hold for corrected operational evidence",
                 "task_id" => submitted["review_task"]["id"]
               },
               submitted["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert held["status"] == "hold"
    resubmitted = submit_evidence(held, context, "corrected readiness bundle")
    refute resubmitted["review_task"]["id"] == submitted["review_task"]["id"]

    assert {:ok, ready, :executed} =
             Shipments.decide_readiness(
               resubmitted["id"],
               %{
                 "decision" => "go",
                 "reason" => "GO after corrected operational evidence",
                 "task_id" => resubmitted["review_task"]["id"]
               },
               resubmitted["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert ready["status"] == "go"
  end

  test "rejects GO after source drift while retaining exact HOLD" do
    context = ProcurementFixtures.context()
    source = ProcurementFixtures.approved_proposal(context)

    {:ok, readiness, :executed} =
      Shipments.create_readiness_case(
        readiness_attrs(source.proposal),
        source.proposal["lock_version"],
        context,
        Ecto.UUID.generate()
      )

    submitted = submit_evidence(readiness, context, "readiness before source drift")
    mutate_proposal_version(context, source.proposal["id"])

    assert {:error, stale_source} =
             Shipments.decide_readiness(
               submitted["id"],
               %{
                 "decision" => "go",
                 "reason" => "Attempt GO after source drift",
                 "task_id" => submitted["review_task"]["id"]
               },
               submitted["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert stale_source.code == "stale_state"

    assert {:ok, held, :executed} =
             Shipments.decide_readiness(
               submitted["id"],
               %{
                 "decision" => "hold",
                 "reason" => "HOLD the drifted source",
                 "task_id" => submitted["review_task"]["id"]
               },
               submitted["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert held["status"] == "hold"
    assert_no_effects(held)
  end

  defp readiness_attrs(proposal, prefix \\ "shipment-readiness") do
    %{
      "stable_identifier" => "#{prefix}-#{System.unique_integer([:positive])}",
      "purchase_commitment_proposal_id" => proposal["id"],
      "expected_proposal_version" => proposal["lock_version"],
      "reason" => "Create a source-bound shipment-readiness case"
    }
  end

  defp submit_evidence(readiness, context, label) do
    evidence_id =
      ProcurementFixtures.persisted_evidence(
        context,
        "shipment_readiness_case",
        readiness["id"],
        label
      )

    {:ok, submitted, :executed} =
      Shipments.submit_readiness_evidence(
        readiness["id"],
        %{"evidence_id" => evidence_id, "reason" => "Attach #{label}"},
        readiness["lock_version"],
        context,
        Ecto.UUID.generate()
      )

    submitted
  end

  defp mutate_proposal_version(context, proposal_id) do
    TenantTransaction.run(context, fn ->
      Repo.update_all(
        from(proposal in PurchaseCommitmentProposalRecord,
          where: proposal.tenant_id == ^context.tenant_id and proposal.id == ^proposal_id
        ),
        inc: [lock_version: 1]
      )
    end)
  end

  defp checklist_status(readiness, code) do
    readiness["checklist_snapshot"]["checks"]
    |> Enum.find(&(&1["code"] == code))
    |> Map.fetch!("status")
  end

  defp assert_no_effects(view) do
    Enum.each(@effect_flags, &refute(view[&1]))
  end

  defp assert_effect_flags(schema, payload_field, id_field, readiness_id, context) do
    records =
      TenantTransaction.run(context, fn ->
        Repo.all(
          from(record in schema,
            where:
              record.tenant_id == ^context.tenant_id and
                field(record, ^id_field) == ^readiness_id
          )
        )
      end)

    assert records != []

    Enum.each(records, fn record ->
      Enum.each(@effect_flags, &refute(Map.fetch!(record, payload_field)[&1]))
    end)
  end

  defp count(schema, context) do
    TenantTransaction.run(context, fn ->
      Repo.aggregate(
        from(record in schema, where: record.tenant_id == ^context.tenant_id),
        :count
      )
    end)
  end
end
