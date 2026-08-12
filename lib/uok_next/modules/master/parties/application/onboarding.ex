defmodule UokNext.Modules.Master.Parties.Application.Onboarding do
  @moduledoc false

  alias UokNext.Kernel.{CommandContext, CommandError, CommandTransaction, TenantTransaction}
  alias UokNext.Modules.Master.Parties.Domain.PartyProfile
  alias UokNext.Modules.Master.Parties.Policies.Authorization
  alias UokNext.Modules.Platform.Evidence.Public, as: Evidence
  alias UokNext.Modules.Platform.Workflow.Public, as: Workflow

  @create_permission "parties:create"
  @read_permission "parties:read"
  @evidence_permission "parties:evidence:submit"
  @approve_permission "parties:approve"
  @review_task_kind "master.parties.onboarding_review"

  @spec create_draft(module(), map(), CommandContext.t(), String.t()) ::
          {:ok, map(), :executed | :replayed} | {:error, CommandError.t()}
  def create_draft(store, attrs, context, idempotency_key) do
    with :ok <- Authorization.require_permission(context, @create_permission),
         {:ok, command} <- validate_create(attrs) do
      payload = Map.put(command, :tenant_id, context.tenant_id)

      CommandTransaction.execute(
        context,
        "master.parties.create_draft",
        idempotency_key,
        payload,
        fn -> create_operation(store, command, context) end
      )
    end
  end

  @spec submit_evidence(module(), String.t(), map(), integer(), CommandContext.t(), String.t()) ::
          {:ok, map(), :executed | :replayed} | {:error, CommandError.t()}
  def submit_evidence(store, party_id, attrs, expected_version, context, idempotency_key) do
    with :ok <- Authorization.require_permission(context, @evidence_permission),
         {:ok, id} <- cast_uuid(party_id),
         {:ok, version} <- cast_version(expected_version) do
      payload = %{party_id: id, expected_version: version, evidence: attrs}

      CommandTransaction.execute(
        context,
        "master.parties.submit_evidence",
        idempotency_key,
        payload,
        fn -> evidence_operation(store, id, attrs, version, context) end
      )
    end
  end

  @spec preflight_evidence(module(), String.t(), integer(), CommandContext.t()) ::
          :ok | {:error, CommandError.t()}
  def preflight_evidence(store, party_id, expected_version, context) do
    with :ok <- Authorization.require_permission(context, @evidence_permission),
         {:ok, id} <- cast_uuid(party_id),
         {:ok, version} <- cast_version(expected_version) do
      TenantTransaction.run(context, fn ->
        preflight_evidence_scoped(store, id, version, context)
      end)
    end
  end

  @spec decide(module(), String.t(), map(), integer(), CommandContext.t(), String.t()) ::
          {:ok, map(), :executed | :replayed} | {:error, CommandError.t()}
  def decide(store, party_id, attrs, expected_version, context, idempotency_key) do
    with :ok <- Authorization.require_permission(context, @approve_permission),
         {:ok, id} <- cast_uuid(party_id),
         {:ok, task_id} <- cast_task_id(attrs),
         {:ok, version} <- cast_version(expected_version) do
      payload = %{party_id: id, task_id: task_id, expected_version: version, decision: attrs}

      CommandTransaction.execute(
        context,
        "master.parties.decide_onboarding",
        idempotency_key,
        payload,
        fn -> decision_operation(store, id, task_id, attrs, version, context) end
      )
    end
  end

  @spec get(module(), String.t(), CommandContext.t()) ::
          {:ok, map()} | {:error, CommandError.t()}
  def get(store, party_id, context) do
    with :ok <- Authorization.require_permission(context, @read_permission),
         {:ok, id} <- cast_uuid(party_id) do
      TenantTransaction.run(context, fn -> get_scoped(store, id, context) end)
    end
  end

  @spec list(module(), pos_integer(), CommandContext.t()) ::
          {:ok, [map()]} | {:error, CommandError.t()}
  def list(store, limit, context) when is_integer(limit) and limit in 1..100 do
    with :ok <- Authorization.require_permission(context, @read_permission) do
      TenantTransaction.run(context, fn ->
        {:ok, store.list(context.tenant_id, limit, context) |> Enum.map(&party_view/1)}
      end)
    end
  end

  def list(_store, _limit, _context),
    do: validation_error(%{limit: ["must be between 1 and 100"]})

  defp get_scoped(store, id, context) do
    case store.fetch(id, context.tenant_id, context) do
      {:ok, party} -> {:ok, party_view(party)}
      :not_found -> not_found()
    end
  end

  defp preflight_evidence_scoped(store, id, expected_version, context) do
    case store.fetch(id, context.tenant_id, context) do
      {:ok, party} ->
        case require_version(party, expected_version) do
          :ok -> map_state_validation(PartyProfile.validate_evidence_state(party.status))
          {:error, %CommandError{} = error} -> {:error, error}
        end

      :not_found ->
        not_found()
    end
  end

  defp create_operation(store, command, context) do
    attrs =
      command
      |> Map.take([:stable_identifier, :legal_name, :country_code, :party_kind])
      |> Map.put(:tenant_id, context.tenant_id)

    case store.create(attrs, context) do
      {:ok, party} ->
        response = party_view(party)

        {:ok, response, audit(party, "create_draft", command.reason),
         [event(party, "party_draft_created")]}

      {:error, details} ->
        validation_error(details)
    end
  end

  defp evidence_operation(store, id, attrs, expected_version, context) do
    with {:ok, party} <- fetch_locked(store, id, context),
         :ok <- require_version(party, expected_version),
         {:ok, evidence} <- verified_evidence(id, attrs, context),
         {:ok, command} <- validate_evidence(party.status, attrs, evidence),
         {:ok, updated} <-
           update_party(
             store,
             party,
             :submit_evidence,
             %{
               status: "evidence_submitted",
               evidence_metadata: command.evidence,
               evidence_submitted_at: DateTime.utc_now()
             },
             context
           ),
         {:ok, task} <- open_review_task(updated, command.reason, context) do
      response = updated |> party_view() |> Map.put("review_task", task)

      audits = [
        audit(updated, "submit_evidence", command.reason),
        task_audit(task, "open", command.reason)
      ]

      events = [event(updated, "onboarding_evidence_submitted"), task_event(task, "opened")]
      {:ok, response, audits, events}
    end
  end

  defp decision_operation(store, id, task_id, attrs, expected_version, context) do
    with {:ok, party} <- fetch_locked(store, id, context),
         :ok <- require_version(party, expected_version),
         {:ok, command} <- validate_decision(party.status, party.evidence_metadata, attrs),
         {:ok, task} <- complete_review_task(task_id, party, command, context),
         {:ok, updated} <-
           update_party(
             store,
             party,
             :decide,
             decision_changes(command, context.actor_id),
             context
           ) do
      event_name =
        if command.decision == "approve", do: "onboarding_approved", else: "onboarding_held"

      response = updated |> party_view() |> Map.put("review_task", task)

      audits = [
        audit(updated, event_name, command.reason),
        task_audit(task, "complete", command.reason)
      ]

      events = [event(updated, event_name), task_event(task, "completed")]
      {:ok, response, audits, events}
    end
  end

  defp open_review_task(party, reason, context) do
    Workflow.open_human_task(
      %{
        task_kind: @review_task_kind,
        subject_type: "party",
        subject_id: party.id,
        subject_version: party.lock_version,
        required_permission: @approve_permission,
        reason: reason
      },
      context
    )
  end

  defp complete_review_task(task_id, party, command, context) do
    Workflow.complete_human_task(
      task_id,
      %{
        subject_type: "party",
        subject_id: party.id,
        subject_version: party.lock_version,
        resolution: command.decision,
        reason: command.reason
      },
      context
    )
  end

  defp decision_changes(command, actor_id) do
    %{
      status: if(command.decision == "approve", do: "approved", else: "hold"),
      decision_reason: command.reason,
      decision_actor_id: actor_id,
      decided_at: DateTime.utc_now()
    }
  end

  defp fetch_locked(store, id, context) do
    case store.fetch_for_update(id, context.tenant_id, context) do
      {:ok, party} -> {:ok, party}
      :not_found -> not_found()
    end
  end

  defp update_party(store, party, action, attrs, context) do
    case store.update(party, action, attrs, context) do
      {:ok, updated} -> {:ok, updated}
      {:error, :stale} -> stale()
      {:error, details} -> validation_error(details)
    end
  end

  defp validate_create(attrs), do: map_validation(PartyProfile.validate_create(attrs))

  defp validate_evidence(status, attrs) do
    map_validation(PartyProfile.validate_evidence(status, attrs))
  end

  defp validate_evidence(status, attrs, evidence) do
    trusted_attrs =
      attrs
      |> Map.put("sha256", evidence["sha256"])
      |> Map.put("classification", evidence["classification"])

    validate_evidence(status, trusted_attrs)
  end

  defp verified_evidence(party_id, attrs, context) do
    evidence_id = Map.get(attrs, "evidence_id", Map.get(attrs, :evidence_id))
    Evidence.get_verified_candidate(evidence_id, party_id, context)
  end

  defp validate_decision(status, evidence, attrs) do
    map_validation(PartyProfile.validate_decision(status, evidence, attrs))
  end

  defp map_validation({:ok, value}), do: {:ok, value}
  defp map_validation({:error, details}), do: validation_error(details)
  defp map_state_validation(:ok), do: :ok
  defp map_state_validation({:error, details}), do: validation_error(details)

  defp cast_uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> validation_error(%{party_id: ["must be a UUID"]})
    end
  end

  defp cast_task_id(attrs) when is_map(attrs) do
    attrs
    |> Map.get("task_id", Map.get(attrs, :task_id))
    |> cast_uuid()
    |> map_task_id_error()
  end

  defp cast_task_id(_attrs), do: validation_error(%{task_id: ["must be a UUID"]})

  defp map_task_id_error({:ok, id}), do: {:ok, id}
  defp map_task_id_error({:error, _error}), do: validation_error(%{task_id: ["must be a UUID"]})

  defp cast_version(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp cast_version(_value),
    do: validation_error(%{expected_version: ["must be a positive integer"]})

  defp require_version(%{lock_version: version}, version), do: :ok
  defp require_version(_party, _expected_version), do: stale()

  defp party_view(party) do
    %{
      "id" => party.id,
      "tenant_id" => party.tenant_id,
      "stable_identifier" => party.stable_identifier,
      "legal_name" => party.legal_name,
      "country_code" => party.country_code,
      "party_kind" => party.party_kind,
      "status" => party.status,
      "evidence_metadata" => party.evidence_metadata,
      "decision_reason" => party.decision_reason,
      "lock_version" => party.lock_version
    }
  end

  defp audit(party, action, reason) do
    %{
      action: "master.parties.#{action}",
      resource_type: "party",
      resource_id: party.id,
      reason: reason,
      classification: "internal",
      metadata: %{"aggregate_version" => party.lock_version, "status" => party.status}
    }
  end

  defp event(party, name) do
    %{
      name: "master.parties.#{name}",
      aggregate_type: "party",
      aggregate_id: party.id,
      aggregate_version: party.lock_version,
      classification: "internal",
      payload: %{"party_id" => party.id, "status" => party.status}
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

  defp validation_error(details) do
    {:error, CommandError.new("validation_failed", "command validation failed", 422, details)}
  end

  defp stale do
    {:error, CommandError.new("stale_state", "record changed since it was read", 409)}
  end

  defp not_found do
    {:error, CommandError.new("not_found", "record was not found", 404)}
  end
end
