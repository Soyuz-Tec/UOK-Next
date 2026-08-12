defmodule UokNext.Modules.Platform.Agents.Application.AgentPlans do
  @moduledoc false

  alias UokNext.Kernel.{CommandContext, CommandError, CommandTransaction, TenantTransaction}
  alias UokNext.Modules.Platform.Agents.Domain.AgentPlan
  alias UokNext.Modules.Platform.Agents.Policies.Authorization
  alias UokNext.Modules.Platform.Workflow.Public, as: Workflow

  @propose_permission "agents:plan:propose"
  @approve_permission "agents:plan:approve"
  @read_permission "agents:plan:read"
  @review_task_kind "platform.agents.plan_review"

  @spec propose(module(), map(), CommandContext.t(), String.t()) :: tuple()
  def propose(store, attrs, context, idempotency_key) do
    with :ok <- Authorization.require_permission(context, @propose_permission),
         {:ok, command} <- validate(AgentPlan.validate_proposal(attrs)) do
      payload = Map.put(command, :tenant_id, context.tenant_id)

      CommandTransaction.execute(
        context,
        "platform.agents.propose_plan",
        idempotency_key,
        payload,
        fn -> propose_operation(store, command, context) end
      )
    end
  end

  @spec decide(module(), String.t(), integer(), map(), CommandContext.t(), String.t()) :: tuple()
  def decide(store, plan_id, expected_version, attrs, context, idempotency_key) do
    with :ok <- Authorization.require_permission(context, @approve_permission),
         {:ok, id} <- validate(AgentPlan.validate_id(plan_id)),
         {:ok, version} <- cast_version(expected_version),
         {:ok, command} <- validate(AgentPlan.validate_decision_input(attrs)) do
      payload = %{plan_id: id, expected_version: version, decision: command}

      CommandTransaction.execute(
        context,
        "platform.agents.decide_plan",
        idempotency_key,
        payload,
        fn -> decision_operation(store, id, version, command, context) end
      )
    end
  end

  @spec get(module(), String.t(), CommandContext.t()) :: {:ok, map()} | {:error, CommandError.t()}
  def get(store, plan_id, context) do
    with :ok <- Authorization.require_permission(context, @read_permission),
         {:ok, id} <- validate(AgentPlan.validate_id(plan_id)) do
      TenantTransaction.run(context, fn -> get_scoped(store, id, context) end)
    end
  end

  defp propose_operation(store, command, context) do
    plan_id = store.new_id()

    with {:ok, task} <- open_review_task(plan_id, command, context),
         {:ok, plan} <- create(store, plan_id, task["id"], command, context) do
      response = plan |> view() |> Map.put("review_task", task)

      audits = [
        audit(plan, "propose", command.reason),
        task_audit(task, "open", command.reason)
      ]

      events = [plan_event(plan, "proposed"), task_event(task, "opened")]
      {:ok, response, audits, events}
    end
  end

  defp open_review_task(plan_id, command, context) do
    Workflow.open_human_task(
      %{
        task_kind: @review_task_kind,
        subject_type: "agent_plan",
        subject_id: plan_id,
        subject_version: 1,
        required_permission: @approve_permission,
        reason: command.reason
      },
      context
    )
  end

  defp create(store, plan_id, task_id, command, context) do
    attrs =
      command
      |> Map.take([
        :runbook_key,
        :runbook_version,
        :subject_type,
        :subject_id,
        :subject_version,
        :step_graph,
        :evidence_ids,
        :plan_sha256
      ])
      |> Map.merge(%{
        id: plan_id,
        tenant_id: context.tenant_id,
        review_task_id: task_id,
        proposed_by_actor_id: context.actor_id,
        proposal_reason: command.reason,
        proposed_at: DateTime.utc_now()
      })

    case store.create(attrs, context) do
      {:ok, plan} -> {:ok, plan}
      {:error, details} -> validation_error(details)
    end
  end

  defp decision_operation(store, id, expected_version, command, context) do
    with {:ok, plan} <- fetch_locked(store, id, context),
         :ok <- require_version(plan, expected_version),
         {:ok, decision} <- validate(AgentPlan.validate_decision(plan, command)),
         :ok <- require_task(plan, decision.task_id),
         {:ok, task} <- complete_review_task(plan, decision, context),
         {:ok, decided} <- persist_decision(store, plan, decision, context) do
      response = decided |> view() |> Map.put("review_task", task)

      audits = [
        audit(decided, "decide", decision.reason),
        task_audit(task, "complete", decision.reason)
      ]

      events = [plan_event(decided, "reviewed"), task_event(task, "completed")]
      {:ok, response, audits, events}
    end
  end

  defp require_task(%{review_task_id: task_id}, task_id), do: :ok
  defp require_task(_plan, _task_id), do: validation_error(%{task_id: ["does not match plan"]})

  defp complete_review_task(plan, decision, context) do
    Workflow.complete_human_task(
      decision.task_id,
      %{
        subject_type: "agent_plan",
        subject_id: plan.id,
        subject_version: plan.lock_version,
        resolution: decision.decision,
        reason: decision.reason
      },
      context
    )
  end

  defp persist_decision(store, plan, decision, context) do
    attrs = %{
      status: if(decision.decision == "approve", do: "approved", else: "hold"),
      decided_by_actor_id: context.actor_id,
      decision_reason: decision.reason,
      decided_at: DateTime.utc_now()
    }

    case store.decide(plan, attrs, context) do
      {:ok, decided} -> {:ok, decided}
      {:error, :stale} -> stale()
      {:error, details} -> validation_error(details)
    end
  end

  defp get_scoped(store, id, context) do
    case store.fetch(id, context.tenant_id, context) do
      {:ok, plan} -> {:ok, view(plan)}
      :not_found -> not_found()
    end
  end

  defp fetch_locked(store, id, context) do
    case store.fetch_for_update(id, context.tenant_id, context) do
      {:ok, plan} -> {:ok, plan}
      :not_found -> not_found()
    end
  end

  defp require_version(%{lock_version: version}, version), do: :ok
  defp require_version(_plan, _version), do: stale()
  defp cast_version(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp cast_version(_value), do: validation_error(%{expected_version: ["must be positive"]})
  defp validate({:ok, value}), do: {:ok, value}
  defp validate({:error, details}), do: validation_error(details)

  defp view(plan) do
    %{
      "id" => plan.id,
      "tenant_id" => plan.tenant_id,
      "runbook_key" => plan.runbook_key,
      "runbook_version" => plan.runbook_version,
      "subject_type" => plan.subject_type,
      "subject_id" => plan.subject_id,
      "subject_version" => plan.subject_version,
      "steps" => plan.step_graph["items"],
      "evidence_ids" => plan.evidence_ids,
      "plan_sha256" => plan.plan_sha256,
      "status" => plan.status,
      "review_task_id" => plan.review_task_id,
      "execution_authorized" => false,
      "lock_version" => plan.lock_version
    }
  end

  defp audit(plan, action, reason) do
    %{
      action: "platform.agents.plan.#{action}",
      resource_type: "agent_plan",
      resource_id: plan.id,
      reason: reason,
      classification: "internal",
      metadata: %{
        "execution_authorized" => false,
        "plan_sha256" => plan.plan_sha256,
        "status" => plan.status
      }
    }
  end

  defp plan_event(plan, lifecycle) do
    %{
      name: "platform.agents.plan_#{lifecycle}",
      aggregate_type: "agent_plan",
      aggregate_id: plan.id,
      aggregate_version: plan.lock_version,
      classification: "internal",
      payload: %{
        "agent_plan_id" => plan.id,
        "execution_authorized" => false,
        "plan_sha256" => plan.plan_sha256,
        "status" => plan.status
      }
    }
  end

  defp task_audit(task, action, reason) do
    %{
      action: "platform.workflow.human_task.#{action}",
      resource_type: "human_task",
      resource_id: task["id"],
      reason: reason,
      classification: "internal",
      metadata: %{
        "status" => task["status"],
        "subject_id" => task["subject_id"],
        "subject_type" => task["subject_type"]
      }
    }
  end

  defp task_event(task, lifecycle) do
    %{
      name: "platform.workflow.human_task_#{lifecycle}",
      aggregate_type: "human_task",
      aggregate_id: task["id"],
      aggregate_version: task["lock_version"],
      classification: "internal",
      payload: %{
        "human_task_id" => task["id"],
        "status" => task["status"],
        "subject_id" => task["subject_id"],
        "subject_type" => task["subject_type"]
      }
    }
  end

  defp validation_error(details),
    do:
      {:error,
       CommandError.new("validation_failed", "agent plan validation failed", 422, details)}

  defp stale, do: {:error, CommandError.new("stale_state", "agent plan changed", 409)}
  defp not_found, do: {:error, CommandError.new("not_found", "record was not found", 404)}
end
