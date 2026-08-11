defmodule UokNext.Kernel.CommandTransaction do
  @moduledoc """
  Executes an attributable, idempotent command and commits its audit and
  outbox records in the same PostgreSQL transaction as business state.
  """

  import Ecto.Query

  alias UokNext.Kernel.{
    AuditEvent,
    CommandContext,
    CommandError,
    CommandReceipt,
    OutboxEvent,
    TenantTransaction
  }

  alias UokNext.Repo

  @idempotency_pattern ~r/^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$/

  @type operation_result ::
          {:ok, map(), map(), [map()]}
          | {:error, CommandError.t()}

  @spec execute(CommandContext.t(), String.t(), String.t(), term(), (-> operation_result())) ::
          {:ok, map(), :executed | :replayed} | {:error, CommandError.t()}
  def execute(context, command_name, idempotency_key, payload, operation)
      when is_function(operation, 0) do
    started_at = System.monotonic_time()

    result =
      with :ok <- validate_input(command_name, idempotency_key) do
        transact(context, command_name, idempotency_key, payload, operation)
      end

    emit_telemetry(command_name, result, started_at)
    result
  end

  defp transact(context, command_name, idempotency_key, payload, operation) do
    payload_hash = payload_hash(payload)

    Repo.transaction(fn ->
      TenantTransaction.activate!(context.tenant_id)

      case claim(context, command_name, idempotency_key, payload_hash) do
        {:new, receipt_id} -> execute_new(context, receipt_id, operation)
        {:replay, response} -> {:ok, response, :replayed}
        {:error, error} -> Repo.rollback(error)
      end
    end)
    |> unwrap_transaction()
  end

  defp execute_new(context, receipt_id, operation) do
    case operation.() do
      {:ok, response, audit, events} ->
        now = DateTime.utc_now()
        insert_audit!(context, receipt_id, audit, now)
        insert_events!(context, receipt_id, events, now)
        complete_receipt!(receipt_id, response, now)
        {:ok, response, :executed}

      {:error, %CommandError{} = error} ->
        Repo.rollback(error)
    end
  end

  defp claim(context, command_name, idempotency_key, payload_hash) do
    now = DateTime.utc_now()

    attrs = %{
      id: Ecto.UUID.generate(),
      tenant_id: context.tenant_id,
      actor_id: context.actor_id,
      correlation_id: context.correlation_id,
      idempotency_key: idempotency_key,
      command_name: command_name,
      payload_hash: payload_hash,
      status: "executing",
      inserted_at: now,
      updated_at: now
    }

    case Repo.insert_all(CommandReceipt, [attrs],
           on_conflict: :nothing,
           conflict_target: [:tenant_id, :idempotency_key],
           returning: [:id]
         ) do
      {1, [%{id: receipt_id}]} -> {:new, receipt_id}
      {0, []} -> existing_claim(context, command_name, idempotency_key, payload_hash)
    end
  end

  defp existing_claim(context, command_name, idempotency_key, payload_hash) do
    receipt =
      Repo.one!(
        from receipt in CommandReceipt,
          where:
            receipt.tenant_id == ^context.tenant_id and
              receipt.idempotency_key == ^idempotency_key,
          lock: "FOR UPDATE"
      )

    if replayable?(receipt, context, command_name, payload_hash) do
      {:replay, receipt.response}
    else
      {:error,
       CommandError.new(
         "idempotency_conflict",
         "idempotency key was already used for a different command",
         409
       )}
    end
  end

  defp replayable?(receipt, context, command_name, payload_hash) do
    receipt.status == "completed" and receipt.actor_id == context.actor_id and
      receipt.command_name == command_name and receipt.payload_hash == payload_hash and
      is_map(receipt.response)
  end

  defp insert_audit!(context, receipt_id, audit, now) do
    Repo.insert_all(AuditEvent, [
      %{
        id: Ecto.UUID.generate(),
        tenant_id: context.tenant_id,
        actor_id: context.actor_id,
        correlation_id: context.correlation_id,
        command_receipt_id: receipt_id,
        action: Map.fetch!(audit, :action),
        resource_type: Map.fetch!(audit, :resource_type),
        resource_id: Map.fetch!(audit, :resource_id),
        outcome: Map.get(audit, :outcome, "succeeded"),
        reason: Map.fetch!(audit, :reason),
        classification: Map.get(audit, :classification, "internal"),
        metadata: Map.get(audit, :metadata, %{}),
        occurred_at: now,
        inserted_at: now
      }
    ])
  end

  defp insert_events!(context, receipt_id, events, now) do
    rows = Enum.map(events, &event_row(&1, context, receipt_id, now))
    Repo.insert_all(OutboxEvent, rows)
  end

  defp event_row(event, context, receipt_id, now) do
    %{
      id: Ecto.UUID.generate(),
      tenant_id: context.tenant_id,
      actor_id: context.actor_id,
      correlation_id: context.correlation_id,
      command_receipt_id: receipt_id,
      event_name: Map.fetch!(event, :name),
      event_version: Map.get(event, :version, 1),
      aggregate_type: Map.fetch!(event, :aggregate_type),
      aggregate_id: Map.fetch!(event, :aggregate_id),
      aggregate_version: Map.fetch!(event, :aggregate_version),
      classification: Map.get(event, :classification, "internal"),
      payload: Map.fetch!(event, :payload),
      status: "pending",
      available_at: now,
      attempt_count: 0,
      inserted_at: now,
      updated_at: now
    }
  end

  defp complete_receipt!(receipt_id, response, now) do
    {1, nil} =
      Repo.update_all(
        from(receipt in CommandReceipt, where: receipt.id == ^receipt_id),
        set: [status: "completed", response: response, updated_at: now]
      )
  end

  defp payload_hash(payload) do
    payload
    |> canonicalize()
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
  end

  defp canonicalize(value) when is_map(value) do
    value
    |> Enum.map(fn {key, item} -> {to_string(key), canonicalize(item)} end)
    |> Enum.sort()
  end

  defp canonicalize(value) when is_list(value), do: Enum.map(value, &canonicalize/1)
  defp canonicalize(value) when is_atom(value), do: Atom.to_string(value)
  defp canonicalize(value), do: value

  defp validate_input(command_name, idempotency_key)
       when is_binary(command_name) and byte_size(command_name) in 1..160 and
              is_binary(idempotency_key) do
    if Regex.match?(@idempotency_pattern, idempotency_key) do
      :ok
    else
      invalid_idempotency_key()
    end
  end

  defp validate_input(_command_name, _idempotency_key), do: invalid_idempotency_key()

  defp invalid_idempotency_key do
    {:error,
     CommandError.new(
       "invalid_idempotency_key",
       "idempotency key must contain 8 to 128 safe characters",
       400
     )}
  end

  defp unwrap_transaction({:ok, result}), do: result
  defp unwrap_transaction({:error, %CommandError{} = error}), do: {:error, error}

  defp emit_telemetry(command_name, result, started_at) do
    duration = System.monotonic_time() - started_at

    :telemetry.execute(
      [:uok_next, :command, :stop],
      %{duration: duration},
      %{command: telemetry_command(command_name), outcome: telemetry_outcome(result)}
    )
  end

  defp telemetry_command(command_name) when is_binary(command_name), do: command_name
  defp telemetry_command(_command_name), do: "invalid"

  defp telemetry_outcome({:ok, _response, disposition}), do: Atom.to_string(disposition)
  defp telemetry_outcome({:error, _error}), do: "rejected"
end
