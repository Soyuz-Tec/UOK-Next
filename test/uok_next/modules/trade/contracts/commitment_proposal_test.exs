defmodule UokNext.Modules.Trade.Contracts.CommitmentProposalTest do
  use UokNext.DataCase, async: true

  import Ecto.Query

  alias UokNext.Kernel.TenantTransaction
  alias UokNext.Modules.Platform.Integrations.Infrastructure.ConnectorReceiptRecord
  alias UokNext.Modules.Trade.Contracts.Infrastructure.PurchaseCommitmentProposalRecord
  alias UokNext.Modules.Trade.Contracts.Public, as: Contracts
  alias UokNext.Modules.Trade.Sourcing.Infrastructure.RfqRecord
  alias UokNext.Modules.Trade.Sourcing.Infrastructure.SupplierQuoteRecord
  alias UokNext.ProcurementFixtures

  test "creates one source-derived proposal and approves its exact evidenced task" do
    context = ProcurementFixtures.context()
    source = ProcurementFixtures.approved_comparison(context)
    key = Ecto.UUID.generate()

    attrs = proposal_attrs(source.comparison)

    assert {:ok, proposal, :executed} =
             Contracts.create_purchase_commitment_proposal(
               attrs,
               source.comparison["lock_version"],
               context,
               key
             )

    assert {:ok, ^proposal, :replayed} =
             Contracts.create_purchase_commitment_proposal(
               attrs,
               source.comparison["lock_version"],
               context,
               key
             )

    assert proposal["status"] == "draft"
    assert proposal["selected_quote_id"] == source.selected_quote["id"]

    assert Decimal.equal?(
             Decimal.new(proposal["source_snapshot"]["unit_price"]),
             Decimal.new("90")
           )

    assert Decimal.equal?(
             Decimal.new(proposal["source_snapshot"]["total_price"]),
             Decimal.new("2250")
           )

    refute proposal["commitment_created"]
    refute proposal["external_effect_created"]

    evidence_id =
      ProcurementFixtures.persisted_evidence(
        context,
        "purchase_commitment_proposal",
        proposal["id"],
        "commitment proposal evidence"
      )

    assert {:ok, submitted, :executed} =
             Contracts.submit_purchase_commitment_evidence(
               proposal["id"],
               %{
                 "evidence_id" => evidence_id,
                 "reason" => "Submit internally reviewed commitment evidence"
               },
               proposal["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert submitted["status"] == "awaiting_review"
    assert submitted["review_task"]["subject_version"] == submitted["lock_version"]

    decision = %{
      "decision" => "approve",
      "reason" => "Approve the exact non-binding proposal",
      "task_id" => submitted["review_task"]["id"]
    }

    decision_key = Ecto.UUID.generate()

    assert {:ok, approved, :executed} =
             Contracts.decide_purchase_commitment_proposal(
               submitted["id"],
               decision,
               submitted["lock_version"],
               context,
               decision_key
             )

    assert {:ok, ^approved, :replayed} =
             Contracts.decide_purchase_commitment_proposal(
               submitted["id"],
               decision,
               submitted["lock_version"],
               context,
               decision_key
             )

    assert approved["status"] == "approved"
    assert approved["review_task"]["resolution"] == "approve"
    refute approved["commitment_created"]
    refute approved["external_effect_created"]
    assert count(PurchaseCommitmentProposalRecord, context) == 1
    assert count(ConnectorReceiptRecord, context) == 0
  end

  test "fails closed for permissions, tenant substitution, source version, and client term injection" do
    context = ProcurementFixtures.context()
    source = ProcurementFixtures.approved_comparison(context)

    injected =
      source.comparison
      |> proposal_attrs()
      |> Map.put("unit_price", "0.01")
      |> Map.put("selected_quote_id", Ecto.UUID.generate())

    assert {:error, invalid} =
             Contracts.create_purchase_commitment_proposal(
               injected,
               source.comparison["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert invalid.code == "validation_failed"

    assert {:error, stale} =
             Contracts.create_purchase_commitment_proposal(
               proposal_attrs(source.comparison),
               source.comparison["lock_version"] + 1,
               context,
               Ecto.UUID.generate()
             )

    assert stale.code == "stale_state"

    foreign = ProcurementFixtures.context()

    assert {:error, hidden} =
             Contracts.create_purchase_commitment_proposal(
               proposal_attrs(source.comparison),
               source.comparison["lock_version"],
               foreign,
               Ecto.UUID.generate()
             )

    assert hidden.code == "not_found"

    denied = ProcurementFixtures.context(%{tenant_id: context.tenant_id, permissions: []})

    assert {:error, forbidden} =
             Contracts.create_purchase_commitment_proposal(
               proposal_attrs(source.comparison),
               source.comparison["lock_version"],
               denied,
               Ecto.UUID.generate()
             )

    assert forbidden.code == "forbidden"

    assert {:ok, _created, :executed} =
             Contracts.create_purchase_commitment_proposal(
               proposal_attrs(source.comparison),
               source.comparison["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert {:error, duplicate} =
             Contracts.create_purchase_commitment_proposal(
               proposal_attrs(source.comparison, "duplicate"),
               source.comparison["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert duplicate.code == "validation_failed"
    assert count(PurchaseCommitmentProposalRecord, context) == 1
  end

  test "rejects changed source approval while preserving an exact HOLD recovery path" do
    context = ProcurementFixtures.context()
    source = ProcurementFixtures.approved_comparison(context)

    {:ok, proposal, :executed} =
      Contracts.create_purchase_commitment_proposal(
        proposal_attrs(source.comparison),
        source.comparison["lock_version"],
        context,
        Ecto.UUID.generate()
      )

    wrong_evidence =
      ProcurementFixtures.persisted_evidence(
        context,
        "supplier_quote",
        source.selected_quote["id"],
        "wrong subject"
      )

    assert {:error, hidden_evidence} =
             Contracts.submit_purchase_commitment_evidence(
               proposal["id"],
               %{"evidence_id" => wrong_evidence, "reason" => "Attempt substituted evidence"},
               proposal["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert hidden_evidence.code == "not_found"

    evidence =
      ProcurementFixtures.persisted_evidence(
        context,
        "purchase_commitment_proposal",
        proposal["id"],
        "correct subject"
      )

    {:ok, submitted, :executed} =
      Contracts.submit_purchase_commitment_evidence(
        proposal["id"],
        %{"evidence_id" => evidence, "reason" => "Submit exact proposal evidence"},
        proposal["lock_version"],
        context,
        Ecto.UUID.generate()
      )

    assert {:error, wrong_task} =
             Contracts.decide_purchase_commitment_proposal(
               submitted["id"],
               %{
                 "decision" => "approve",
                 "reason" => "Attempt task substitution",
                 "task_id" => Ecto.UUID.generate()
               },
               submitted["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert wrong_task.code == "not_found"

    mutate_quote_price(context, source.selected_quote["id"])

    decision = %{
      "decision" => "approve",
      "reason" => "Attempt approval after source drift",
      "task_id" => submitted["review_task"]["id"]
    }

    assert {:error, changed_source} =
             Contracts.decide_purchase_commitment_proposal(
               submitted["id"],
               decision,
               submitted["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert changed_source.code == "state_conflict"

    hold = %{decision | "decision" => "hold", "reason" => "Hold the proposal after source drift"}

    assert {:ok, held, :executed} =
             Contracts.decide_purchase_commitment_proposal(
               submitted["id"],
               hold,
               submitted["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert held["status"] == "hold"
    refute held["commitment_created"]
  end

  test "rejects an RFQ version that drifted after comparison approval" do
    context = ProcurementFixtures.context()
    source = ProcurementFixtures.approved_comparison(context)

    mutate_rfq_version(context, source.rfq["id"])

    assert {:error, stale_source} =
             Contracts.create_purchase_commitment_proposal(
               proposal_attrs(source.comparison),
               source.comparison["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert stale_source.code == "stale_state"
    assert count(PurchaseCommitmentProposalRecord, context) == 0
  end

  defp proposal_attrs(comparison, suffix \\ "proposal") do
    %{
      "stable_identifier" => "#{suffix}-#{System.unique_integer([:positive])}",
      "quote_comparison_id" => comparison["id"],
      "expected_comparison_version" => comparison["lock_version"],
      "reason" => "Create a source-bound non-binding commitment proposal"
    }
  end

  defp mutate_quote_price(context, quote_id) do
    TenantTransaction.run(context, fn ->
      Repo.update_all(
        from(quote in SupplierQuoteRecord,
          where: quote.tenant_id == ^context.tenant_id and quote.id == ^quote_id
        ),
        set: [unit_price: Decimal.new("91")]
      )
    end)
  end

  defp mutate_rfq_version(context, rfq_id) do
    TenantTransaction.run(context, fn ->
      Repo.update_all(
        from(rfq in RfqRecord,
          where: rfq.tenant_id == ^context.tenant_id and rfq.id == ^rfq_id
        ),
        inc: [lock_version: 1]
      )
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
