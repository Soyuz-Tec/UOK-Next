defmodule UokNext.Modules.Trade.Shipments.Application.ReadinessCases do
  @moduledoc false

  alias UokNext.Kernel.{CommandTransaction, TenantTransaction}
  alias UokNext.Modules.Platform.Evidence.Public, as: Evidence
  alias UokNext.Modules.Platform.Workflow.Public, as: Workflow
  alias UokNext.Modules.Trade.Contracts.Public, as: Contracts
  alias UokNext.Modules.Trade.Shipments.Application.ReadinessSupport, as: Support
  alias UokNext.Modules.Trade.Shipments.Domain.ReadinessCase
  alias UokNext.Modules.Trade.Shipments.Policies.Authorization

  @create_permission "shipments:readiness:create"
  @read_permission "shipments:readiness:read"
  @evidence_permission "shipments:readiness:evidence:submit"
  @decide_permission "shipments:readiness:decide"
  @task_kind "trade.shipments.shipment_readiness_review"

  def create(store, attrs, expected_version, context, key) do
    with :ok <- Authorization.require_permission(context, @create_permission),
         {:ok, version} <- Support.cast_version(expected_version),
         {:ok, command} <- Support.validate(ReadinessCase.validate_create(attrs)) do
      payload =
        command
        |> Map.put(:tenant_id, context.tenant_id)
        |> Map.put(:expected_proposal_version, version)

      CommandTransaction.execute(
        context,
        "trade.shipments.create_shipment_readiness_case",
        key,
        payload,
        fn -> create_operation(store, command, version, context) end
      )
    end
  end

  def preflight_evidence(store, readiness_id, expected_version, context) do
    with :ok <- Authorization.require_permission(context, @evidence_permission),
         {:ok, id} <- Support.cast_uuid(readiness_id, :readiness_id),
         {:ok, version} <- Support.cast_version(expected_version) do
      TenantTransaction.run(context, fn -> preflight_scoped(store, id, version, context) end)
    end
  end

  def submit_evidence(store, readiness_id, attrs, expected_version, context, key) do
    with :ok <- Authorization.require_permission(context, @evidence_permission),
         {:ok, id} <- Support.cast_uuid(readiness_id, :readiness_id),
         {:ok, version} <- Support.cast_version(expected_version) do
      payload = %{readiness_id: id, expected_version: version, evidence: attrs}

      CommandTransaction.execute(
        context,
        "trade.shipments.submit_shipment_readiness_evidence",
        key,
        payload,
        fn -> evidence_operation(store, id, attrs, version, context) end
      )
    end
  end

  def decide(store, readiness_id, attrs, expected_version, context, key) do
    with :ok <- Authorization.require_permission(context, @decide_permission),
         {:ok, id} <- Support.cast_uuid(readiness_id, :readiness_id),
         {:ok, task_id} <- task_id(attrs),
         {:ok, version} <- Support.cast_version(expected_version) do
      payload = %{readiness_id: id, task_id: task_id, expected_version: version, decision: attrs}

      CommandTransaction.execute(
        context,
        "trade.shipments.decide_shipment_readiness",
        key,
        payload,
        fn -> decision_operation(store, id, task_id, attrs, version, context) end
      )
    end
  end

  def list(store, limit, context) when is_integer(limit) and limit in 1..100 do
    with :ok <- Authorization.require_permission(context, @read_permission) do
      TenantTransaction.run(context, fn ->
        {:ok,
         store.list(context.tenant_id, limit, context) |> Enum.map(&Support.readiness_view/1)}
      end)
    end
  end

  def list(_store, _limit, _context), do: Support.validation(%{limit: ["must be 1 to 100"]})

  defp create_operation(store, command, version, context) do
    with {:ok, source} <-
           Contracts.require_shipment_readiness_source(
             command.purchase_commitment_proposal_id,
             version,
             context
           ),
         {:ok, readiness} <- persist_create(store, command, source, context) do
      {:ok, Support.readiness_view(readiness),
       Support.audit(readiness, "shipment_readiness_case_created", command.reason),
       [Support.event(readiness, "shipment_readiness_case_created")]}
    end
  end

  defp preflight_scoped(store, id, version, context) do
    with {:ok, readiness} <- Support.fetch(store.fetch(id, context.tenant_id, context, [])),
         :ok <- Support.require_version(readiness, version),
         :ok <- state_validation(ReadinessCase.validate_evidence_state(readiness.status)) do
      require_current_source(readiness, context)
    end
  end

  defp evidence_operation(store, id, attrs, version, context) do
    with {:ok, readiness} <- fetch_locked(store, id, context),
         :ok <- Support.require_version(readiness, version),
         {:ok, command} <-
           Support.validate(ReadinessCase.validate_evidence(readiness.status, attrs)),
         :ok <- require_current_source(readiness, context),
         {:ok, evidence} <-
           Evidence.get_verified_candidate(
             command.evidence_id,
             "shipment_readiness_case",
             readiness.id,
             context
           ),
         {:ok, updated} <-
           Support.write(store.update(readiness, evidence_changes(evidence), context)),
         {:ok, task} <- open_task(updated, command.reason, context) do
      response = Support.readiness_view(updated) |> Map.put("review_task", task)

      audits = [
        Support.audit(updated, "shipment_readiness_submitted", command.reason),
        Support.task_audit(task, "open", command.reason)
      ]

      events = [
        Support.event(updated, "shipment_readiness_submitted"),
        Support.task_event(task, "opened")
      ]

      {:ok, response, audits, events}
    end
  end

  defp decision_operation(store, id, task_id, attrs, version, context) do
    with {:ok, readiness} <- fetch_locked(store, id, context),
         :ok <- Support.require_version(readiness, version),
         {:ok, command} <-
           Support.validate(ReadinessCase.validate_decision(readiness.status, attrs)),
         :ok <- require_go_preconditions(readiness, command, context),
         {:ok, task} <- complete_task(task_id, readiness, command, context),
         {:ok, updated} <- update_decision(store, readiness, command, context) do
      response = Support.readiness_view(updated) |> Map.put("review_task", task)

      lifecycle =
        if command.decision == "go", do: "shipment_readiness_go", else: "shipment_readiness_held"

      audits = [
        Support.audit(updated, lifecycle, command.reason),
        Support.task_audit(task, "complete", command.reason)
      ]

      events = [
        Support.event(updated, lifecycle),
        Support.task_event(task, "completed")
      ]

      {:ok, response, audits, events}
    end
  end

  defp persist_create(store, command, source, context) do
    attrs = %{
      tenant_id: context.tenant_id,
      stable_identifier: command.stable_identifier,
      purchase_commitment_proposal_id: source["purchase_commitment_proposal_id"],
      purchase_commitment_proposal_version: source["purchase_commitment_proposal_version"],
      source_snapshot: source,
      checklist_snapshot: Support.initial_checklist(),
      created_by_actor_id: context.actor_id
    }

    Support.write(store.create(attrs, context))
  end

  defp fetch_locked(store, id, context) do
    store.fetch(id, context.tenant_id, context, lock: true) |> Support.fetch()
  end

  defp require_current_source(readiness, context) do
    with {:ok, source} <-
           Contracts.require_shipment_readiness_source(
             readiness.purchase_commitment_proposal_id,
             readiness.purchase_commitment_proposal_version,
             context
           ) do
      if source == readiness.source_snapshot,
        do: :ok,
        else: Support.conflict("shipment readiness source changed after creation")
    end
  end

  defp require_go_preconditions(readiness, %{decision: "go"}, context) do
    with :ok <- require_current_source(readiness, context),
         :ok <- Support.require_ready(readiness.checklist_snapshot),
         true <- is_map(readiness.evidence_metadata) do
      :ok
    else
      false -> Support.conflict("shipment readiness evidence is missing")
      {:error, _error} = error -> error
    end
  end

  defp require_go_preconditions(_readiness, %{decision: "hold"}, _context), do: :ok

  defp evidence_changes(evidence) do
    %{
      status: "awaiting_review",
      checklist_snapshot: Support.ready_checklist(),
      submitted_at: DateTime.utc_now(),
      evidence_metadata: %{
        "evidence_id" => evidence["id"],
        "sha256" => evidence["sha256"],
        "classification" => evidence["classification"]
      },
      decision_reason: nil,
      decision_actor_id: nil,
      decided_at: nil
    }
  end

  defp open_task(readiness, reason, context) do
    Workflow.open_human_task(
      %{
        task_kind: @task_kind,
        subject_type: "shipment_readiness_case",
        subject_id: readiness.id,
        subject_version: readiness.lock_version,
        required_permission: @decide_permission,
        reason: reason
      },
      context
    )
  end

  defp complete_task(task_id, readiness, command, context) do
    Workflow.complete_human_task(
      task_id,
      %{
        subject_type: "shipment_readiness_case",
        subject_id: readiness.id,
        subject_version: readiness.lock_version,
        resolution: if(command.decision == "go", do: "approve", else: "hold"),
        reason: command.reason
      },
      context
    )
  end

  defp update_decision(store, readiness, command, context) do
    attrs = %{
      status: command.decision,
      decision_reason: command.reason,
      decision_actor_id: context.actor_id,
      decided_at: DateTime.utc_now()
    }

    Support.write(store.update(readiness, attrs, context))
  end

  defp task_id(attrs) when is_map(attrs) do
    Support.cast_uuid(Map.get(attrs, "task_id", Map.get(attrs, :task_id)), :task_id)
  end

  defp task_id(_attrs), do: Support.validation(%{task_id: ["must be a UUID"]})
  defp state_validation(:ok), do: :ok
  defp state_validation({:error, details}), do: Support.validation(details)
end
