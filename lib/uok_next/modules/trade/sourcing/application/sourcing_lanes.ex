defmodule UokNext.Modules.Trade.Sourcing.Application.SourcingLanes do
  @moduledoc false

  alias UokNext.Kernel.{CommandContext, CommandError, CommandTransaction, TenantTransaction}
  alias UokNext.Modules.Master.Locations.Public, as: Locations
  alias UokNext.Modules.Master.Parties.Public, as: Parties
  alias UokNext.Modules.Master.Products.Public, as: Products
  alias UokNext.Modules.Platform.Evidence.Public, as: Evidence
  alias UokNext.Modules.Platform.Workflow.Public, as: Workflow
  alias UokNext.Modules.Trade.Sourcing.Domain.SourcingLane
  alias UokNext.Modules.Trade.Sourcing.Policies.Authorization

  @create_permission "sourcing:lanes:create"
  @read_permission "sourcing:lanes:read"
  @evidence_permission "sourcing:lanes:evidence:submit"
  @approve_permission "sourcing:lanes:approve"
  @review_task_kind "trade.sourcing.lane_review"

  @spec create(module(), map(), CommandContext.t(), String.t()) :: tuple()
  def create(store, attrs, context, idempotency_key) do
    with :ok <- Authorization.require_permission(context, @create_permission),
         {:ok, command} <- validate(SourcingLane.validate_create(attrs)) do
      payload = Map.put(command, :tenant_id, context.tenant_id)

      CommandTransaction.execute(
        context,
        "trade.sourcing.create_lane",
        idempotency_key,
        payload,
        fn -> create_operation(store, command, context) end
      )
    end
  end

  @spec submit_evidence(module(), String.t(), map(), integer(), CommandContext.t(), String.t()) ::
          tuple()
  def submit_evidence(store, lane_id, attrs, expected_version, context, idempotency_key) do
    with :ok <- Authorization.require_permission(context, @evidence_permission),
         {:ok, id} <- cast_uuid(lane_id, :lane_id),
         {:ok, version} <- cast_version(expected_version) do
      payload = %{lane_id: id, expected_version: version, evidence: attrs}

      CommandTransaction.execute(
        context,
        "trade.sourcing.submit_lane_evidence",
        idempotency_key,
        payload,
        fn -> evidence_operation(store, id, attrs, version, context) end
      )
    end
  end

  @spec preflight_evidence(module(), String.t(), integer(), CommandContext.t()) :: tuple()
  def preflight_evidence(store, lane_id, expected_version, context) do
    with :ok <- Authorization.require_permission(context, @evidence_permission),
         {:ok, id} <- cast_uuid(lane_id, :lane_id),
         {:ok, version} <- cast_version(expected_version) do
      TenantTransaction.run(context, fn -> preflight_scoped(store, id, version, context) end)
    end
  end

  @spec decide(module(), String.t(), map(), integer(), CommandContext.t(), String.t()) :: tuple()
  def decide(store, lane_id, attrs, expected_version, context, idempotency_key) do
    with :ok <- Authorization.require_permission(context, @approve_permission),
         {:ok, id} <- cast_uuid(lane_id, :lane_id),
         {:ok, task_id} <- cast_task_id(attrs),
         {:ok, version} <- cast_version(expected_version) do
      payload = %{lane_id: id, task_id: task_id, expected_version: version, decision: attrs}

      CommandTransaction.execute(
        context,
        "trade.sourcing.decide_lane",
        idempotency_key,
        payload,
        fn -> decision_operation(store, id, task_id, attrs, version, context) end
      )
    end
  end

  @spec get(module(), String.t(), CommandContext.t()) :: tuple()
  def get(store, lane_id, context) do
    with :ok <- Authorization.require_permission(context, @read_permission),
         {:ok, id} <- cast_uuid(lane_id, :lane_id) do
      TenantTransaction.run(context, fn -> get_scoped(store, id, context) end)
    end
  end

  @spec list(module(), pos_integer(), CommandContext.t()) :: tuple()
  def list(store, limit, context) when is_integer(limit) and limit in 1..100 do
    with :ok <- Authorization.require_permission(context, @read_permission) do
      TenantTransaction.run(context, fn ->
        {:ok, store.list(context.tenant_id, limit, context) |> Enum.map(&view/1)}
      end)
    end
  end

  def list(_store, _limit, _context), do: validation_error(%{limit: ["must be 1 to 100"]})

  defp create_operation(store, command, context) do
    with :ok <- require_references(command, context),
         {:ok, lane} <- create_lane(store, command, context) do
      {:ok, view(lane), audit(lane, "create", command.reason), [event(lane, "lane_created")]}
    end
  end

  defp require_references(command, context) do
    with {:ok, _party} <- Parties.require_approved(command.supplier_party_id, context),
         {:ok, _product} <- Products.require_active(command.product_id, context),
         {:ok, _origin} <- Locations.require_active(command.origin_location_id, context),
         {:ok, _destination} <-
           Locations.require_active(command.destination_location_id, context) do
      :ok
    end
  end

  defp create_lane(store, command, context) do
    attrs = command |> Map.delete(:reason) |> Map.put(:tenant_id, context.tenant_id)

    case store.create(attrs, context) do
      {:ok, lane} -> {:ok, lane}
      {:error, details} -> validation_error(details)
    end
  end

  defp evidence_operation(store, id, attrs, expected_version, context) do
    with {:ok, lane} <- fetch_locked(store, id, context),
         :ok <- require_version(lane, expected_version),
         {:ok, evidence} <- verified_evidence(id, attrs, context),
         {:ok, command} <- validate_evidence(lane.status, attrs, evidence),
         {:ok, updated} <- update_lane(store, lane, evidence_changes(command), context),
         {:ok, task} <- open_review_task(updated, command.reason, context) do
      response = updated |> view() |> Map.put("review_task", task)

      audits = [
        audit(updated, "submit_evidence", command.reason),
        task_audit(task, "open", command.reason)
      ]

      events = [event(updated, "lane_evidence_submitted"), task_event(task, "opened")]
      {:ok, response, audits, events}
    end
  end

  defp decision_operation(store, id, task_id, attrs, expected_version, context) do
    with {:ok, lane} <- fetch_locked(store, id, context),
         :ok <- require_version(lane, expected_version),
         {:ok, command} <-
           validate(SourcingLane.validate_decision(lane.status, lane.evidence_metadata, attrs)),
         {:ok, task} <- complete_review_task(task_id, lane, command, context),
         {:ok, updated} <-
           update_lane(store, lane, decision_changes(command, context.actor_id), context) do
      lifecycle = if command.decision == "approve", do: "lane_approved", else: "lane_held"
      response = updated |> view() |> Map.put("review_task", task)

      audits = [
        audit(updated, lifecycle, command.reason),
        task_audit(task, "complete", command.reason)
      ]

      events = [event(updated, lifecycle), task_event(task, "completed")]
      {:ok, response, audits, events}
    end
  end

  defp get_scoped(store, id, context) do
    case store.fetch(id, context.tenant_id, context) do
      {:ok, lane} -> {:ok, view(lane)}
      :not_found -> not_found()
    end
  end

  defp preflight_scoped(store, id, expected_version, context) do
    with {:ok, lane} <- fetch(store, id, context),
         :ok <- require_version(lane, expected_version) do
      state_validation(SourcingLane.validate_evidence_state(lane.status))
    end
  end

  defp fetch(store, id, context) do
    case store.fetch(id, context.tenant_id, context) do
      {:ok, lane} -> {:ok, lane}
      :not_found -> not_found()
    end
  end

  defp fetch_locked(store, id, context) do
    case store.fetch_for_update(id, context.tenant_id, context) do
      {:ok, lane} -> {:ok, lane}
      :not_found -> not_found()
    end
  end

  defp verified_evidence(lane_id, attrs, context) do
    evidence_id = Map.get(attrs, "evidence_id", Map.get(attrs, :evidence_id))
    Evidence.get_verified_candidate(evidence_id, "sourcing_lane", lane_id, context)
  end

  defp validate_evidence(status, attrs, evidence) do
    trusted_attrs =
      attrs
      |> Map.put("sha256", evidence["sha256"])
      |> Map.put("classification", evidence["classification"])

    validate(SourcingLane.validate_evidence(status, trusted_attrs))
  end

  defp evidence_changes(command) do
    %{
      status: "evidence_submitted",
      evidence_metadata: command.evidence,
      evidence_submitted_at: DateTime.utc_now(),
      decision_reason: nil,
      decision_actor_id: nil,
      decided_at: nil
    }
  end

  defp decision_changes(command, actor_id) do
    %{
      status: if(command.decision == "approve", do: "approved", else: "hold"),
      decision_reason: command.reason,
      decision_actor_id: actor_id,
      decided_at: DateTime.utc_now()
    }
  end

  defp update_lane(store, lane, attrs, context) do
    case store.update(lane, attrs, context) do
      {:ok, updated} -> {:ok, updated}
      {:error, :stale} -> stale()
      {:error, details} -> validation_error(details)
    end
  end

  defp open_review_task(lane, reason, context) do
    Workflow.open_human_task(
      %{
        task_kind: @review_task_kind,
        subject_type: "sourcing_lane",
        subject_id: lane.id,
        subject_version: lane.lock_version,
        required_permission: @approve_permission,
        reason: reason
      },
      context
    )
  end

  defp complete_review_task(task_id, lane, command, context) do
    Workflow.complete_human_task(
      task_id,
      %{
        subject_type: "sourcing_lane",
        subject_id: lane.id,
        subject_version: lane.lock_version,
        resolution: command.decision,
        reason: command.reason
      },
      context
    )
  end

  defp view(lane) do
    %{
      "id" => lane.id,
      "tenant_id" => lane.tenant_id,
      "stable_identifier" => lane.stable_identifier,
      "name" => lane.name,
      "supplier_party_id" => lane.supplier_party_id,
      "product_id" => lane.product_id,
      "origin_location_id" => lane.origin_location_id,
      "destination_location_id" => lane.destination_location_id,
      "status" => lane.status,
      "evidence_metadata" => lane.evidence_metadata,
      "decision_reason" => lane.decision_reason,
      "lock_version" => lane.lock_version
    }
  end

  defp audit(lane, action, reason) do
    %{
      action: "trade.sourcing.#{action}",
      resource_type: "sourcing_lane",
      resource_id: lane.id,
      reason: reason,
      classification: "internal",
      metadata: %{"status" => lane.status, "aggregate_version" => lane.lock_version}
    }
  end

  defp event(lane, lifecycle) do
    %{
      name: "trade.sourcing.#{lifecycle}",
      aggregate_type: "sourcing_lane",
      aggregate_id: lane.id,
      aggregate_version: lane.lock_version,
      classification: "internal",
      payload: %{"sourcing_lane_id" => lane.id, "status" => lane.status}
    }
  end

  defp task_audit(task, action, reason) do
    %{
      action: "platform.workflow.human_task.#{action}",
      resource_type: "human_task",
      resource_id: task["id"],
      reason: reason,
      classification: "internal",
      metadata: %{"status" => task["status"], "subject_id" => task["subject_id"]}
    }
  end

  defp task_event(task, lifecycle) do
    %{
      name: "platform.workflow.human_task_#{lifecycle}",
      aggregate_type: "human_task",
      aggregate_id: task["id"],
      aggregate_version: task["lock_version"],
      classification: "internal",
      payload: %{"human_task_id" => task["id"], "status" => task["status"]}
    }
  end

  defp cast_task_id(attrs) when is_map(attrs) do
    value = Map.get(attrs, "task_id", Map.get(attrs, :task_id))
    cast_uuid(value, :task_id)
  end

  defp cast_task_id(_attrs), do: validation_error(%{task_id: ["must be a UUID"]})

  defp cast_uuid(value, field) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> validation_error(%{field => ["must be a UUID"]})
    end
  end

  defp cast_version(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp cast_version(_value), do: validation_error(%{expected_version: ["must be positive"]})
  defp require_version(%{lock_version: version}, version), do: :ok
  defp require_version(_lane, _expected), do: stale()
  defp validate({:ok, value}), do: {:ok, value}
  defp validate({:error, details}), do: validation_error(details)
  defp state_validation(:ok), do: :ok
  defp state_validation({:error, details}), do: validation_error(details)

  defp validation_error(details),
    do:
      {:error, CommandError.new("validation_failed", "sourcing validation failed", 422, details)}

  defp stale, do: {:error, CommandError.new("stale_state", "record changed since read", 409)}
  defp not_found, do: {:error, CommandError.new("not_found", "record was not found", 404)}
end
