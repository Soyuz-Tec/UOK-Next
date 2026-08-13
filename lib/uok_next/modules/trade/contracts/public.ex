defmodule UokNext.Modules.Trade.Contracts.Public do
  @moduledoc "Supported command and query boundary for `trade.contracts`."

  alias UokNext.Modules.Trade.Contracts.Application.PurchaseCommitmentProposals
  alias UokNext.Modules.Trade.Contracts.Application.ShipmentReadinessSources
  alias UokNext.Modules.Trade.Contracts.Infrastructure.EctoCommitmentStore

  def create_purchase_commitment_proposal(attrs, expected_version, context, key) do
    PurchaseCommitmentProposals.create(
      EctoCommitmentStore,
      attrs,
      expected_version,
      context,
      key
    )
  end

  def preflight_purchase_commitment_evidence(id, expected_version, context) do
    PurchaseCommitmentProposals.preflight_evidence(
      EctoCommitmentStore,
      id,
      expected_version,
      context
    )
  end

  def submit_purchase_commitment_evidence(id, attrs, expected_version, context, key) do
    PurchaseCommitmentProposals.submit_evidence(
      EctoCommitmentStore,
      id,
      attrs,
      expected_version,
      context,
      key
    )
  end

  def decide_purchase_commitment_proposal(id, attrs, expected_version, context, key) do
    PurchaseCommitmentProposals.decide(
      EctoCommitmentStore,
      id,
      attrs,
      expected_version,
      context,
      key
    )
  end

  def list_purchase_commitment_proposals(limit, context) do
    PurchaseCommitmentProposals.list(EctoCommitmentStore, limit, context)
  end

  def require_shipment_readiness_source(id, expected_version, context) do
    ShipmentReadinessSources.require_current(EctoCommitmentStore, id, expected_version, context)
  end
end
