defmodule UokNext.Modules.Trade.Sourcing.Public do
  @moduledoc "Supported command and query boundary for `trade.sourcing`."

  alias UokNext.Modules.Trade.Sourcing.Application.{
    CommitmentSources,
    QuoteComparisons,
    Requisitions,
    Rfqs,
    SourcingLanes,
    SupplierQuotes
  }

  alias UokNext.Modules.Trade.Sourcing.Infrastructure.{
    EctoProcurementStore,
    EctoSourcingLaneStore
  }

  @spec create_lane(map(), UokNext.Kernel.CommandContext.t(), String.t()) :: tuple()
  def create_lane(attrs, context, idempotency_key),
    do: SourcingLanes.create(EctoSourcingLaneStore, attrs, context, idempotency_key)

  @spec preflight_evidence(String.t(), integer(), UokNext.Kernel.CommandContext.t()) :: tuple()
  def preflight_evidence(lane_id, expected_version, context),
    do:
      SourcingLanes.preflight_evidence(
        EctoSourcingLaneStore,
        lane_id,
        expected_version,
        context
      )

  @spec submit_evidence(
          String.t(),
          map(),
          integer(),
          UokNext.Kernel.CommandContext.t(),
          String.t()
        ) ::
          tuple()
  def submit_evidence(lane_id, attrs, expected_version, context, idempotency_key),
    do:
      SourcingLanes.submit_evidence(
        EctoSourcingLaneStore,
        lane_id,
        attrs,
        expected_version,
        context,
        idempotency_key
      )

  @spec decide(String.t(), map(), integer(), UokNext.Kernel.CommandContext.t(), String.t()) ::
          tuple()
  def decide(lane_id, attrs, expected_version, context, idempotency_key),
    do:
      SourcingLanes.decide(
        EctoSourcingLaneStore,
        lane_id,
        attrs,
        expected_version,
        context,
        idempotency_key
      )

  @spec get(String.t(), UokNext.Kernel.CommandContext.t()) :: tuple()
  def get(lane_id, context), do: SourcingLanes.get(EctoSourcingLaneStore, lane_id, context)

  @spec list(pos_integer(), UokNext.Kernel.CommandContext.t()) :: tuple()
  def list(limit, context), do: SourcingLanes.list(EctoSourcingLaneStore, limit, context)

  def create_requisition(attrs, context, key),
    do: Requisitions.create(EctoProcurementStore, attrs, context, key)

  def list_requisitions(limit, context),
    do: Requisitions.list(EctoProcurementStore, limit, context)

  def create_rfq(attrs, expected_version, context, key),
    do: Rfqs.create(EctoProcurementStore, attrs, expected_version, context, key)

  def list_rfqs(limit, context), do: Rfqs.list(EctoProcurementStore, limit, context)

  def create_supplier_quote(attrs, context, key),
    do: SupplierQuotes.create(EctoProcurementStore, attrs, context, key)

  def preflight_quote_evidence(quote_id, expected_version, context),
    do:
      SupplierQuotes.preflight_evidence(EctoProcurementStore, quote_id, expected_version, context)

  def submit_quote_evidence(quote_id, attrs, expected_version, context, key),
    do:
      SupplierQuotes.submit_evidence(
        EctoProcurementStore,
        quote_id,
        attrs,
        expected_version,
        context,
        key
      )

  def list_supplier_quotes(rfq_id, limit, context),
    do: SupplierQuotes.list(EctoProcurementStore, rfq_id, limit, context)

  def create_quote_comparison(attrs, expected_version, context, key),
    do: QuoteComparisons.create(EctoProcurementStore, attrs, expected_version, context, key)

  def decide_quote_comparison(id, attrs, expected_version, context, key),
    do: QuoteComparisons.decide(EctoProcurementStore, id, attrs, expected_version, context, key)

  def list_quote_comparisons(limit, context),
    do: QuoteComparisons.list(EctoProcurementStore, limit, context)

  @doc "Returns a locked, current, server-derived source for a commitment proposal."
  def require_commitment_source(comparison_id, expected_version, context) do
    CommitmentSources.require_current(
      EctoProcurementStore,
      comparison_id,
      expected_version,
      context
    )
  end
end
