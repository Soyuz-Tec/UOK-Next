defmodule UokNext.Modules.Trade.Sourcing.Public do
  @moduledoc "Supported command and query boundary for `trade.sourcing`."

  alias UokNext.Modules.Trade.Sourcing.Application.SourcingLanes
  alias UokNext.Modules.Trade.Sourcing.Infrastructure.EctoSourcingLaneStore

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
end
