defmodule UokNext.Modules.Platform.Integrations.Application.ConnectorReceipts do
  @moduledoc false

  alias UokNext.Kernel.{CommandContext, CommandError, CommandTransaction, TenantTransaction}
  alias UokNext.Modules.Platform.Integrations.Domain.ConnectorReceipt
  alias UokNext.Modules.Platform.Integrations.Policies.Authorization

  @attempt_permission "integrations:attempt"
  @reconcile_permission "integrations:reconcile"
  @read_permission "integrations:read"

  @spec begin_attempt(module(), map(), CommandContext.t(), String.t()) :: tuple()
  def begin_attempt(store, attrs, context, idempotency_key) do
    with :ok <- Authorization.require_permission(context, @attempt_permission),
         {:ok, command} <- validate(ConnectorReceipt.validate_attempt(attrs)),
         :ok <- general_role(command.connector_role) do
      execute_attempt(store, command, context, idempotency_key)
    end
  end

  @doc false
  @spec begin_communication_attempt(module(), map(), CommandContext.t(), String.t()) :: tuple()
  def begin_communication_attempt(store, attrs, context, idempotency_key) do
    with :ok <- Authorization.require_permission(context, "communications:deliver"),
         {:ok, command} <- validate(ConnectorReceipt.validate_attempt(attrs)),
         :ok <- communication_role(command.connector_role) do
      execute_attempt(store, command, context, idempotency_key)
    end
  end

  defp execute_attempt(store, command, context, idempotency_key) do
    payload = Map.put(command, :tenant_id, context.tenant_id)

    CommandTransaction.execute(
      context,
      "platform.integrations.begin_attempt",
      idempotency_key,
      payload,
      fn -> begin_operation(store, command, context) end
    )
  end

  @spec reconcile(module(), String.t(), integer(), map(), CommandContext.t(), String.t()) ::
          tuple()
  def reconcile(store, receipt_id, expected_version, attrs, context, idempotency_key) do
    with :ok <- Authorization.require_permission(context, @reconcile_permission),
         {:ok, id} <- validate(ConnectorReceipt.validate_id(receipt_id)),
         {:ok, version} <- cast_version(expected_version),
         :ok <- require_general_receipt(store, id, context) do
      execute_reconciliation(store, id, version, attrs, context, idempotency_key)
    end
  end

  @doc false
  @spec reconcile_communication_attempt(
          module(),
          String.t(),
          integer(),
          map(),
          CommandContext.t(),
          String.t(),
          atom()
        ) :: tuple()
  def reconcile_communication_attempt(store, id, version, attrs, context, key, authority) do
    permission =
      case authority do
        :delivery -> "communications:deliver"
        :reconciliation -> "communications:reconcile"
      end

    with :ok <- Authorization.require_permission(context, permission),
         {:ok, id} <- validate(ConnectorReceipt.validate_id(id)),
         {:ok, version} <- cast_version(version),
         :ok <- require_communication_receipt(store, id, context) do
      execute_reconciliation(store, id, version, attrs, context, key)
    end
  end

  defp execute_reconciliation(store, id, version, attrs, context, idempotency_key) do
    payload = %{receipt_id: id, expected_version: version, outcome: attrs}

    CommandTransaction.execute(
      context,
      "platform.integrations.reconcile_attempt",
      idempotency_key,
      payload,
      fn -> reconcile_operation(store, id, version, attrs, context) end
    )
  end

  @spec get(module(), String.t(), CommandContext.t()) :: {:ok, map()} | {:error, CommandError.t()}
  def get(store, receipt_id, context) do
    with :ok <- Authorization.require_permission(context, @read_permission),
         {:ok, id} <- validate(ConnectorReceipt.validate_id(receipt_id)),
         :ok <- require_general_receipt(store, id, context) do
      TenantTransaction.run(context, fn -> get_scoped(store, id, context) end)
    end
  end

  defp begin_operation(store, command, context) do
    with {:ok, attempt_number} <- next_attempt(store, command, context),
         {:ok, receipt} <- create(store, command, attempt_number, context) do
      response = view(receipt)

      {:ok, response, audit(receipt, "begin_attempt", command.reason),
       [event(receipt, "attempted")]}
    end
  end

  defp next_attempt(_store, %{previous_receipt_id: nil}, _context), do: {:ok, 1}

  defp next_attempt(store, command, context) do
    with {:ok, previous} <- fetch_locked(store, command.previous_receipt_id, context),
         :ok <- validate_rule(ConnectorReceipt.validate_retry(previous, command)) do
      {:ok, previous.attempt_number + 1}
    end
  end

  defp create(store, command, attempt_number, context) do
    now = DateTime.utc_now()

    attrs =
      command
      |> Map.take([
        :connector_role,
        :operation,
        :delivery_key,
        :request_sha256,
        :subject_type,
        :subject_id,
        :subject_version,
        :timeout_ms,
        :previous_receipt_id
      ])
      |> Map.merge(%{
        tenant_id: context.tenant_id,
        attempt_number: attempt_number,
        deadline_at: DateTime.add(now, command.timeout_ms, :millisecond),
        attempted_by_actor_id: context.actor_id,
        attempted_at: now
      })

    case store.create(attrs, context) do
      {:ok, receipt} -> {:ok, receipt}
      {:error, details} -> validation_error(details)
    end
  end

  defp reconcile_operation(store, id, expected_version, attrs, context) do
    with {:ok, receipt} <- fetch_locked(store, id, context),
         :ok <- require_version(receipt, expected_version),
         {:ok, outcome} <-
           validate(ConnectorReceipt.validate_outcome(receipt, attrs, DateTime.utc_now())),
         {:ok, reconciled} <- persist_outcome(store, receipt, outcome, context) do
      response = view(reconciled)

      {:ok, response, audit(reconciled, "reconcile_attempt", outcome.outcome_reason),
       [event(reconciled, "reconciled")]}
    end
  end

  defp persist_outcome(store, receipt, outcome, context) do
    attrs =
      Map.merge(outcome, %{
        reconciled_by_actor_id: context.actor_id,
        reconciled_at: DateTime.utc_now()
      })

    case store.reconcile(receipt, attrs, context) do
      {:ok, reconciled} -> {:ok, reconciled}
      {:error, :stale} -> stale()
      {:error, details} -> validation_error(details)
    end
  end

  defp get_scoped(store, id, context) do
    case store.fetch(id, context.tenant_id, context) do
      {:ok, receipt} -> {:ok, view(receipt)}
      :not_found -> not_found()
    end
  end

  defp fetch_locked(store, id, context) do
    case store.fetch_for_update(id, context.tenant_id, context) do
      {:ok, receipt} -> {:ok, receipt}
      :not_found -> not_found()
    end
  end

  defp require_version(%{lock_version: version}, version), do: :ok
  defp require_version(_receipt, _version), do: stale()
  defp cast_version(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp cast_version(_value), do: validation_error(%{expected_version: ["must be positive"]})
  defp validate({:ok, value}), do: {:ok, value}
  defp validate({:error, details}), do: validation_error(details)
  defp validate_rule(:ok), do: :ok
  defp validate_rule({:error, details}), do: validation_error(details)

  @doc false
  @spec view(map()) :: map()
  def view(receipt) do
    %{
      "id" => receipt.id,
      "tenant_id" => receipt.tenant_id,
      "connector_role" => receipt.connector_role,
      "operation" => receipt.operation,
      "delivery_key" => receipt.delivery_key,
      "attempt_number" => receipt.attempt_number,
      "request_sha256" => receipt.request_sha256,
      "subject_type" => receipt.subject_type,
      "subject_id" => receipt.subject_id,
      "subject_version" => receipt.subject_version,
      "status" => receipt.status,
      "deadline_at" => DateTime.to_iso8601(receipt.deadline_at),
      "previous_receipt_id" => receipt.previous_receipt_id,
      "response_sha256" => receipt.response_sha256,
      "external_reference" => receipt.external_reference,
      "retry_after_seconds" => receipt.retry_after_seconds,
      "lock_version" => receipt.lock_version
    }
  end

  defp audit(receipt, action, reason) do
    %{
      action: "platform.integrations.#{action}",
      resource_type: "integration_receipt",
      resource_id: receipt.id,
      reason: reason,
      classification: "internal",
      metadata: %{
        "attempt_number" => receipt.attempt_number,
        "connector_role" => receipt.connector_role,
        "status" => receipt.status
      }
    }
  end

  defp event(receipt, lifecycle) do
    %{
      name: "platform.integrations.connector_#{lifecycle}",
      aggregate_type: "integration_receipt",
      aggregate_id: receipt.id,
      aggregate_version: receipt.lock_version,
      classification: "internal",
      payload: %{
        "attempt_number" => receipt.attempt_number,
        "connector_role" => receipt.connector_role,
        "integration_receipt_id" => receipt.id,
        "status" => receipt.status
      }
    }
  end

  defp require_general_receipt(store, id, context) do
    require_receipt_role(store, id, context, &general_role/1)
  end

  defp require_communication_receipt(store, id, context) do
    require_receipt_role(store, id, context, &communication_role/1)
  end

  defp require_receipt_role(store, id, context, rule) do
    TenantTransaction.run(context, fn ->
      case store.fetch(id, context.tenant_id, context) do
        {:ok, receipt} -> rule.(receipt.connector_role)
        :not_found -> not_found()
      end
    end)
  end

  defp general_role("communications_system"), do: reserved_role()
  defp general_role(_role), do: :ok
  defp communication_role("communications_system"), do: :ok
  defp communication_role(_role), do: reserved_role()

  defp reserved_role,
    do: {:error, CommandError.new("forbidden", "use the governed communications contract", 403)}

  defp validation_error(details),
    do:
      {:error,
       CommandError.new("validation_failed", "connector receipt validation failed", 422, details)}

  defp stale, do: {:error, CommandError.new("stale_state", "connector receipt changed", 409)}
  defp not_found, do: {:error, CommandError.new("not_found", "record was not found", 404)}
end
