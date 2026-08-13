defmodule UokNext.Modules.Trade.Shipments.Application.ReadinessSupport do
  @moduledoc false

  alias UokNext.Kernel.CommandError

  @effect_flags %{
    "shipment_created" => false,
    "dispatch_created" => false,
    "inventory_effect_created" => false,
    "finance_effect_created" => false,
    "external_effect_created" => false
  }

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

  def initial_checklist do
    checklist([
      check("approved_proposal", "passed"),
      check("current_commercial_source", "passed"),
      check("verified_commercial_evidence", "passed"),
      check("verified_operational_readiness_evidence", "pending")
    ])
  end

  def ready_checklist do
    checklist([
      check("approved_proposal", "passed"),
      check("current_commercial_source", "passed"),
      check("verified_commercial_evidence", "passed"),
      check("verified_operational_readiness_evidence", "passed")
    ])
  end

  def require_ready(%{"formula_version" => 1, "checks" => checks}) when is_list(checks) do
    required =
      MapSet.new(
        ~w(approved_proposal current_commercial_source verified_commercial_evidence verified_operational_readiness_evidence)
      )

    passed =
      checks
      |> Enum.filter(&(is_map(&1) and &1["status"] == "passed"))
      |> Enum.map(& &1["code"])
      |> MapSet.new()

    if passed == required, do: :ok, else: conflict("shipment readiness checklist is incomplete")
  end

  def require_ready(_snapshot),
    do: conflict("shipment readiness checklist failed integrity checks")

  def readiness_view(record) do
    %{
      "id" => record.id,
      "tenant_id" => record.tenant_id,
      "stable_identifier" => record.stable_identifier,
      "purchase_commitment_proposal_id" => record.purchase_commitment_proposal_id,
      "purchase_commitment_proposal_version" => record.purchase_commitment_proposal_version,
      "source_snapshot" => record.source_snapshot,
      "checklist_snapshot" => record.checklist_snapshot,
      "status" => record.status,
      "evidence_metadata" => record.evidence_metadata,
      "decision_reason" => record.decision_reason,
      "lock_version" => record.lock_version
    }
    |> Map.merge(@effect_flags)
  end

  def audit(record, lifecycle, reason) do
    %{
      action: "trade.shipments.#{lifecycle}",
      resource_type: "shipment_readiness_case",
      resource_id: record.id,
      reason: reason,
      classification: "confidential",
      metadata:
        Map.merge(@effect_flags, %{
          "status" => record.status,
          "aggregate_version" => record.lock_version,
          "checklist_formula_version" => record.checklist_snapshot["formula_version"]
        })
    }
  end

  def event(record, lifecycle) do
    %{
      name: "trade.shipments.#{lifecycle}",
      aggregate_type: "shipment_readiness_case",
      aggregate_id: record.id,
      aggregate_version: record.lock_version,
      classification: "confidential",
      payload:
        Map.merge(@effect_flags, %{
          "shipment_readiness_case_id" => record.id,
          "status" => record.status
        })
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
     CommandError.new("validation_failed", "shipment readiness validation failed", 422, details)}
  end

  def stale, do: {:error, CommandError.new("stale_state", "record changed since read", 409)}
  def not_found, do: {:error, CommandError.new("not_found", "record was not found", 404)}
  def conflict(message), do: {:error, CommandError.new("state_conflict", message, 409)}

  defp checklist(checks), do: %{"formula_version" => 1, "checks" => checks}
  defp check(code, status), do: %{"code" => code, "status" => status, "authority" => "server"}
end
