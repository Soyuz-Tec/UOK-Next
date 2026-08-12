defmodule UokNext.Modules.Platform.Agents.Public do
  @moduledoc """
  Supported boundary for governed, non-executing agent plan operations.
  """

  alias UokNext.Modules.Platform.Agents.Application.AgentPlans
  alias UokNext.Modules.Platform.Agents.Infrastructure.EctoAgentPlanStore

  @spec propose_plan(map(), UokNext.Kernel.CommandContext.t(), String.t()) :: tuple()
  def propose_plan(attrs, context, idempotency_key) do
    AgentPlans.propose(EctoAgentPlanStore, attrs, context, idempotency_key)
  end

  @spec decide_plan(String.t(), integer(), map(), UokNext.Kernel.CommandContext.t(), String.t()) ::
          tuple()
  def decide_plan(plan_id, expected_version, attrs, context, idempotency_key) do
    AgentPlans.decide(
      EctoAgentPlanStore,
      plan_id,
      expected_version,
      attrs,
      context,
      idempotency_key
    )
  end

  @spec get_plan(String.t(), UokNext.Kernel.CommandContext.t()) :: tuple()
  def get_plan(plan_id, context), do: AgentPlans.get(EctoAgentPlanStore, plan_id, context)
end
