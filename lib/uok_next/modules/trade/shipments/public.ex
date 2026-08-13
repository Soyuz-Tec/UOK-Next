defmodule UokNext.Modules.Trade.Shipments.Public do
  @moduledoc "Supported command and query boundary for `trade.shipments`."

  alias UokNext.Modules.Trade.Shipments.Application.ReadinessCases
  alias UokNext.Modules.Trade.Shipments.Infrastructure.EctoReadinessStore

  def create_readiness_case(attrs, expected_version, context, key) do
    ReadinessCases.create(EctoReadinessStore, attrs, expected_version, context, key)
  end

  def preflight_readiness_evidence(id, expected_version, context) do
    ReadinessCases.preflight_evidence(EctoReadinessStore, id, expected_version, context)
  end

  def submit_readiness_evidence(id, attrs, expected_version, context, key) do
    ReadinessCases.submit_evidence(
      EctoReadinessStore,
      id,
      attrs,
      expected_version,
      context,
      key
    )
  end

  def decide_readiness(id, attrs, expected_version, context, key) do
    ReadinessCases.decide(EctoReadinessStore, id, attrs, expected_version, context, key)
  end

  def list_readiness_cases(limit, context) do
    ReadinessCases.list(EctoReadinessStore, limit, context)
  end
end
