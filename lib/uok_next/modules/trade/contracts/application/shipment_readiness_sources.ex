defmodule UokNext.Modules.Trade.Contracts.Application.ShipmentReadinessSources do
  @moduledoc false

  alias UokNext.Kernel.TenantTransaction
  alias UokNext.Modules.Trade.Contracts.Application.CommitmentSupport, as: Support
  alias UokNext.Modules.Trade.Contracts.Policies.Authorization
  alias UokNext.Modules.Trade.Sourcing.Public, as: Sourcing

  @read_permission "contracts:commitment-proposals:read"

  def require_current(store, proposal_id, expected_version, context) do
    with :ok <- Authorization.require_permission(context, @read_permission),
         {:ok, id} <- Support.cast_uuid(proposal_id, :proposal_id),
         {:ok, version} <- Support.cast_version(expected_version) do
      TenantTransaction.run(context, fn -> source(store, id, version, context, lock: true) end)
    end
  end

  def project_current(store, proposal_id, expected_version, context) do
    with :ok <- Authorization.require_permission(context, @read_permission),
         {:ok, id} <- Support.cast_uuid(proposal_id, :proposal_id),
         {:ok, version} <- Support.cast_version(expected_version) do
      TenantTransaction.run(context, fn -> source(store, id, version, context, []) end)
    end
  end

  defp source(store, id, version, context, options) do
    with {:ok, proposal} <- fetch_proposal(store, id, context, options),
         :ok <- Support.require_version(proposal, version),
         :ok <- require_approved(proposal),
         {:ok, commercial_source} <- current_commercial_source(proposal, context, options) do
      {:ok, source_view(proposal, commercial_source)}
    end
  end

  defp fetch_proposal(store, id, context, options) do
    store.fetch(id, context.tenant_id, context, options) |> Support.fetch()
  end

  defp require_approved(%{status: "approved", evidence_metadata: metadata})
       when is_map(metadata),
       do: :ok

  defp require_approved(_proposal),
    do: Support.conflict("purchase commitment proposal is not approved and evidenced")

  defp current_commercial_source(proposal, context, options) do
    query =
      if Keyword.get(options, :lock, false),
        do: &Sourcing.require_commitment_source/3,
        else: &Sourcing.project_commitment_source/3

    with {:ok, source} <-
           query.(proposal.quote_comparison_id, proposal.quote_comparison_version, context) do
      if source == proposal.source_snapshot,
        do: {:ok, source},
        else: Support.conflict("purchase commitment proposal source changed after approval")
    end
  end

  defp source_view(proposal, commercial_source) do
    %{
      "readiness_formula_version" => 1,
      "purchase_commitment_proposal_id" => proposal.id,
      "purchase_commitment_proposal_version" => proposal.lock_version,
      "proposal_evidence" => bounded_evidence(proposal.evidence_metadata),
      "commercial_source" => commercial_source
    }
  end

  defp bounded_evidence(metadata),
    do: Map.take(metadata, ["evidence_id", "sha256", "classification"])
end
