defmodule UokNext.Modules.Trade.Sourcing.Application.ProcurementSupport do
  @moduledoc false

  alias UokNext.Kernel.{CommandContext, CommandError}

  def authorize(context, permission) do
    if CommandContext.permitted?(context, permission),
      do: :ok,
      else: {:error, CommandError.new("forbidden", "command is not permitted", 403)}
  end

  def cast_uuid(value, field) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> validation(%{field => ["must be a UUID"]})
    end
  end

  def cast_version(value) when is_integer(value) and value > 0, do: {:ok, value}
  def cast_version(_value), do: validation(%{expected_version: ["must be positive"]})
  def require_version(%{lock_version: version}, version), do: :ok
  def require_version(_record, _expected), do: stale()

  def validate({:ok, value}), do: {:ok, value}
  def validate({:error, details}), do: validation(details)

  def fetch(result) do
    case result do
      {:ok, record} -> {:ok, record}
      :not_found -> not_found()
    end
  end

  def write(result) do
    case result do
      {:ok, record} -> {:ok, record}
      {:error, :stale} -> stale()
      {:error, details} -> validation(details)
    end
  end

  def validation(details),
    do:
      {:error,
       CommandError.new("validation_failed", "procurement validation failed", 422, details)}

  def stale, do: {:error, CommandError.new("stale_state", "record changed since read", 409)}
  def not_found, do: {:error, CommandError.new("not_found", "record was not found", 404)}
  def conflict(message), do: {:error, CommandError.new("state_conflict", message, 409)}

  def requisition_view(record) do
    %{
      "id" => record.id,
      "tenant_id" => record.tenant_id,
      "stable_identifier" => record.stable_identifier,
      "sourcing_lane_id" => record.sourcing_lane_id,
      "sourcing_lane_version" => record.sourcing_lane_version,
      "quantity" => Decimal.to_string(record.quantity, :normal),
      "unit_code" => record.unit_code,
      "required_by" => Date.to_iso8601(record.required_by),
      "status" => record.status,
      "lock_version" => record.lock_version
    }
  end

  def rfq_view(record) do
    %{
      "id" => record.id,
      "tenant_id" => record.tenant_id,
      "stable_identifier" => record.stable_identifier,
      "requisition_id" => record.requisition_id,
      "requisition_version" => record.requisition_version,
      "settlement_currency_code" => record.settlement_currency_code,
      "response_deadline" => DateTime.to_iso8601(record.response_deadline),
      "status" => record.status,
      "lock_version" => record.lock_version
    }
  end

  def quote_view(record) do
    %{
      "id" => record.id,
      "tenant_id" => record.tenant_id,
      "stable_identifier" => record.stable_identifier,
      "rfq_id" => record.rfq_id,
      "supplier_party_id" => record.supplier_party_id,
      "quoted_quantity" => Decimal.to_string(record.quoted_quantity, :normal),
      "unit_price" => Decimal.to_string(record.unit_price, :normal),
      "currency_code" => record.currency_code,
      "delivery_days" => record.delivery_days,
      "status" => record.status,
      "evidence_metadata" => record.evidence_metadata,
      "lock_version" => record.lock_version
    }
  end

  def comparison_view(record) do
    %{
      "id" => record.id,
      "tenant_id" => record.tenant_id,
      "stable_identifier" => record.stable_identifier,
      "rfq_id" => record.rfq_id,
      "rfq_version" => record.rfq_version,
      "recommended_quote_id" => record.recommended_quote_id,
      "ranking_snapshot" => record.ranking_snapshot,
      "status" => record.status,
      "decision_reason" => record.decision_reason,
      "lock_version" => record.lock_version
    }
  end

  def audit(resource_type, record, action, reason) do
    %{
      action: "trade.sourcing.#{action}",
      resource_type: resource_type,
      resource_id: record.id,
      reason: reason,
      classification: "confidential",
      metadata: %{"status" => record.status, "aggregate_version" => record.lock_version}
    }
  end

  def event(aggregate_type, record, lifecycle) do
    %{
      name: "trade.sourcing.#{lifecycle}",
      aggregate_type: aggregate_type,
      aggregate_id: record.id,
      aggregate_version: record.lock_version,
      classification: "confidential",
      payload: %{"#{aggregate_type}_id" => record.id, "status" => record.status}
    }
  end

  def task_audit(task, action, reason) do
    %{
      action: "platform.workflow.human_task.#{action}",
      resource_type: "human_task",
      resource_id: task["id"],
      reason: reason,
      classification: "internal",
      metadata: %{"status" => task["status"], "subject_id" => task["subject_id"]}
    }
  end

  def task_event(task, lifecycle) do
    %{
      name: "platform.workflow.human_task_#{lifecycle}",
      aggregate_type: "human_task",
      aggregate_id: task["id"],
      aggregate_version: task["lock_version"],
      classification: "internal",
      payload: %{"human_task_id" => task["id"], "status" => task["status"]}
    }
  end
end
