defmodule UokNext.Modules.Platform.Evidence.Application.EvidenceCandidates do
  @moduledoc false

  alias UokNext.Kernel.{CommandContext, CommandError, CommandTransaction, TenantTransaction}
  alias UokNext.Modules.Platform.Evidence.Domain.EvidenceCandidate
  alias UokNext.Modules.Platform.Evidence.Policies.Authorization

  @upload_permission "evidence:upload"
  @read_permission "evidence:read"

  @spec prepare(module(), map(), CommandContext.t(), String.t()) :: tuple()
  def prepare(store, attrs, context, idempotency_key) do
    with :ok <- Authorization.require_permission(context, @upload_permission),
         {:ok, command} <- validate(EvidenceCandidate.validate_prepare(attrs)) do
      payload = Map.put(command, :tenant_id, context.tenant_id)

      CommandTransaction.execute(
        context,
        "platform.evidence.prepare_candidate",
        idempotency_key,
        payload,
        fn -> prepare_operation(store, command, context) end
      )
    end
  end

  @spec verify(module(), String.t(), map(), CommandContext.t(), String.t()) :: tuple()
  def verify(store, candidate_id, receipt, context, idempotency_key) do
    with :ok <- Authorization.require_permission(context, @upload_permission),
         {:ok, id} <- cast_uuid(candidate_id) do
      payload = %{candidate_id: id, storage_receipt: receipt}

      CommandTransaction.execute(
        context,
        "platform.evidence.verify_candidate",
        idempotency_key,
        payload,
        fn -> verify_operation(store, id, receipt, context) end
      )
    end
  end

  @spec get_verified(module(), String.t(), String.t(), String.t(), CommandContext.t()) :: tuple()
  def get_verified(store, id, subject_type, subject_id, context) do
    with :ok <- Authorization.require_permission(context, @read_permission),
         {:ok, candidate_id} <- cast_uuid(id),
         {:ok, governed_subject_id} <- cast_uuid(subject_id) do
      TenantTransaction.run(context, fn ->
        get_verified_scoped(store, candidate_id, subject_type, governed_subject_id, context)
      end)
    end
  end

  @spec list_for_subject(module(), String.t(), String.t(), CommandContext.t()) :: tuple()
  def list_for_subject(store, subject_type, subject_id, context) do
    with :ok <- Authorization.require_permission(context, @read_permission),
         {:ok, governed_subject_id} <- cast_uuid(subject_id) do
      TenantTransaction.run(context, fn ->
        records =
          store.list_for_subject(context.tenant_id, subject_type, governed_subject_id, context)

        {:ok, Enum.map(records, &view/1)}
      end)
    end
  end

  defp prepare_operation(store, command, context) do
    attrs = command |> Map.delete(:reason) |> Map.put(:tenant_id, context.tenant_id)

    case store.create(attrs, context) do
      {:ok, candidate} ->
        {:ok, view(candidate), audit(candidate, "prepare", command.reason),
         [event(candidate, "candidate_prepared")]}

      {:error, details} ->
        validation_error(details)
    end
  end

  defp verify_operation(store, id, receipt, context) do
    with {:ok, candidate} <- fetch_locked(store, id, context),
         {:ok, bounded_receipt} <-
           validate(EvidenceCandidate.validate_verification(candidate.state, receipt)),
         {:ok, verified} <- persist_verification(store, candidate, bounded_receipt, context) do
      {:ok, view(verified), audit(verified, "verify", "Verify stored evidence bytes"),
       [event(verified, "candidate_verified")]}
    end
  end

  defp get_verified_scoped(store, id, subject_type, subject_id, context) do
    case store.fetch(id, context.tenant_id, context) do
      {:ok, %{state: "verified", subject_type: ^subject_type, subject_id: ^subject_id} = record} ->
        {:ok, view(record)}

      _missing_or_mismatch ->
        not_found()
    end
  end

  defp fetch_locked(store, id, context) do
    case store.fetch_for_update(id, context.tenant_id, context) do
      {:ok, record} -> {:ok, record}
      :not_found -> not_found()
    end
  end

  defp persist_verification(store, candidate, receipt, context) do
    attrs = %{state: "verified", storage_receipt: receipt, verified_at: DateTime.utc_now()}

    case store.verify(candidate, attrs, context) do
      {:ok, verified} -> {:ok, verified}
      {:error, :stale} -> stale()
      {:error, details} -> validation_error(details)
    end
  end

  defp view(candidate) do
    %{
      "id" => candidate.id,
      "tenant_id" => candidate.tenant_id,
      "subject_type" => candidate.subject_type,
      "subject_id" => candidate.subject_id,
      "content_type" => candidate.content_type,
      "byte_size" => candidate.byte_size,
      "sha256" => candidate.sha256,
      "classification" => candidate.classification,
      "state" => candidate.state,
      "lock_version" => candidate.lock_version
    }
  end

  defp audit(candidate, action, reason) do
    %{
      action: "platform.evidence.#{action}",
      resource_type: "evidence_object",
      resource_id: candidate.id,
      reason: reason,
      classification: candidate.classification,
      metadata: %{"state" => candidate.state, "subject_id" => candidate.subject_id}
    }
  end

  defp event(candidate, lifecycle) do
    %{
      name: "platform.evidence.#{lifecycle}",
      aggregate_type: "evidence_object",
      aggregate_id: candidate.id,
      aggregate_version: candidate.lock_version,
      classification: candidate.classification,
      payload: %{
        "evidence_id" => candidate.id,
        "state" => candidate.state,
        "subject_id" => candidate.subject_id
      }
    }
  end

  defp validate({:ok, value}), do: {:ok, value}
  defp validate({:error, details}), do: validation_error(details)

  defp cast_uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> validation_error(%{id: ["must be a UUID"]})
    end
  end

  defp validation_error(details),
    do:
      {:error, CommandError.new("validation_failed", "evidence validation failed", 422, details)}

  defp stale, do: {:error, CommandError.new("stale_state", "evidence changed", 409)}
  defp not_found, do: {:error, CommandError.new("not_found", "record was not found", 404)}
end
