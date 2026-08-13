defmodule UokNext.Modules.Trade.Contracts.Application.CommitmentSupport do
  @moduledoc false

  alias UokNext.Kernel.CommandError

  def cast_uuid(value, field) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> validation(%{field => ["must be a UUID"]})
    end
  end

  def cast_version(value) when is_integer(value) and value > 0, do: {:ok, value}
  def cast_version(_value), do: validation(%{expected_version: ["must be positive"]})
  def require_version(%{lock_version: version}, version), do: :ok
  def require_version(_record, _version), do: stale()
  def validate({:ok, value}), do: {:ok, value}
  def validate({:error, details}), do: validation(details)

  def fetch({:ok, record}), do: {:ok, record}
  def fetch(:not_found), do: not_found()

  def write({:ok, record}), do: {:ok, record}
  def write({:error, :stale}), do: stale()
  def write({:error, details}), do: validation(details)

  def proposal_view(record) do
    %{
      "id" => record.id,
      "tenant_id" => record.tenant_id,
      "stable_identifier" => record.stable_identifier,
      "quote_comparison_id" => record.quote_comparison_id,
      "quote_comparison_version" => record.quote_comparison_version,
      "selected_quote_id" => record.selected_quote_id,
      "selected_quote_version" => record.selected_quote_version,
      "source_snapshot" => record.source_snapshot,
      "status" => record.status,
      "evidence_metadata" => record.evidence_metadata,
      "decision_reason" => record.decision_reason,
      "lock_version" => record.lock_version,
      "commitment_created" => false,
      "external_effect_created" => false
    }
  end

  def audit(record, lifecycle, reason) do
    %{
      action: "trade.contracts.#{lifecycle}",
      resource_type: "purchase_commitment_proposal",
      resource_id: record.id,
      reason: reason,
      classification: "confidential",
      metadata: %{
        "status" => record.status,
        "aggregate_version" => record.lock_version,
        "commitment_created" => false,
        "external_effect_created" => false
      }
    }
  end

  def event(record, lifecycle) do
    %{
      name: "trade.contracts.#{lifecycle}",
      aggregate_type: "purchase_commitment_proposal",
      aggregate_id: record.id,
      aggregate_version: record.lock_version,
      classification: "confidential",
      payload: %{
        "purchase_commitment_proposal_id" => record.id,
        "status" => record.status,
        "commitment_created" => false,
        "external_effect_created" => false
      }
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

  def validation(details) do
    {:error,
     CommandError.new(
       "validation_failed",
       "purchase commitment proposal validation failed",
       422,
       details
     )}
  end

  def stale, do: {:error, CommandError.new("stale_state", "record changed since read", 409)}
  def not_found, do: {:error, CommandError.new("not_found", "record was not found", 404)}
  def conflict(message), do: {:error, CommandError.new("state_conflict", message, 409)}
end
