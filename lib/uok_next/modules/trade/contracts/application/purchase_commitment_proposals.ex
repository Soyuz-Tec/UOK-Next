defmodule UokNext.Modules.Trade.Contracts.Application.PurchaseCommitmentProposals do
  @moduledoc false

  alias UokNext.Kernel.{CommandTransaction, TenantTransaction}
  alias UokNext.Modules.Platform.Evidence.Public, as: Evidence
  alias UokNext.Modules.Platform.Workflow.Public, as: Workflow
  alias UokNext.Modules.Trade.Contracts.Application.CommitmentSupport, as: Support
  alias UokNext.Modules.Trade.Contracts.Domain.CommitmentProposal
  alias UokNext.Modules.Trade.Contracts.Policies.Authorization
  alias UokNext.Modules.Trade.Sourcing.Public, as: Sourcing

  @create_permission "contracts:commitment-proposals:create"
  @read_permission "contracts:commitment-proposals:read"
  @evidence_permission "contracts:commitment-proposals:evidence:submit"
  @approve_permission "contracts:commitment-proposals:approve"
  @task_kind "trade.contracts.purchase_commitment_proposal_review"

  def create(store, attrs, expected_version, context, key) do
    with :ok <- Authorization.require_permission(context, @create_permission),
         {:ok, version} <- Support.cast_version(expected_version),
         {:ok, command} <- Support.validate(CommitmentProposal.validate_create(attrs)) do
      payload =
        command
        |> Map.put(:tenant_id, context.tenant_id)
        |> Map.put(:expected_comparison_version, version)

      CommandTransaction.execute(
        context,
        "trade.contracts.create_purchase_commitment_proposal",
        key,
        payload,
        fn -> create_operation(store, command, version, context) end
      )
    end
  end

  def preflight_evidence(store, proposal_id, expected_version, context) do
    with :ok <- Authorization.require_permission(context, @evidence_permission),
         {:ok, id} <- Support.cast_uuid(proposal_id, :proposal_id),
         {:ok, version} <- Support.cast_version(expected_version) do
      TenantTransaction.run(context, fn -> preflight_scoped(store, id, version, context) end)
    end
  end

  def submit_evidence(store, proposal_id, attrs, expected_version, context, key) do
    with :ok <- Authorization.require_permission(context, @evidence_permission),
         {:ok, id} <- Support.cast_uuid(proposal_id, :proposal_id),
         {:ok, version} <- Support.cast_version(expected_version) do
      payload = %{proposal_id: id, expected_version: version, evidence: attrs}

      CommandTransaction.execute(
        context,
        "trade.contracts.submit_purchase_commitment_proposal_evidence",
        key,
        payload,
        fn -> evidence_operation(store, id, attrs, version, context) end
      )
    end
  end

  def decide(store, proposal_id, attrs, expected_version, context, key) do
    with :ok <- Authorization.require_permission(context, @approve_permission),
         {:ok, id} <- Support.cast_uuid(proposal_id, :proposal_id),
         {:ok, task_id} <- task_id(attrs),
         {:ok, version} <- Support.cast_version(expected_version) do
      payload = %{proposal_id: id, task_id: task_id, expected_version: version, decision: attrs}

      CommandTransaction.execute(
        context,
        "trade.contracts.decide_purchase_commitment_proposal",
        key,
        payload,
        fn -> decision_operation(store, id, task_id, attrs, version, context) end
      )
    end
  end

  def list(store, limit, context) when is_integer(limit) and limit in 1..100 do
    with :ok <- Authorization.require_permission(context, @read_permission) do
      TenantTransaction.run(context, fn ->
        {:ok, store.list(context.tenant_id, limit, context) |> Enum.map(&Support.proposal_view/1)}
      end)
    end
  end

  def list(_store, _limit, _context), do: Support.validation(%{limit: ["must be 1 to 100"]})

  defp create_operation(store, command, version, context) do
    with {:ok, source} <-
           Sourcing.require_commitment_source(command.quote_comparison_id, version, context),
         {:ok, proposal} <- persist_create(store, command, source, context) do
      {:ok, Support.proposal_view(proposal),
       Support.audit(proposal, "purchase_commitment_proposal_created", command.reason),
       [Support.event(proposal, "purchase_commitment_proposal_created")]}
    end
  end

  defp preflight_scoped(store, id, version, context) do
    with {:ok, proposal} <- Support.fetch(store.fetch(id, context.tenant_id, context, [])),
         :ok <- Support.require_version(proposal, version),
         :ok <- state_validation(CommitmentProposal.validate_evidence_state(proposal.status)) do
      require_current_source(proposal, context)
    end
  end

  defp evidence_operation(store, id, attrs, version, context) do
    with {:ok, proposal} <- fetch_locked(store, id, context),
         :ok <- Support.require_version(proposal, version),
         {:ok, command} <-
           Support.validate(CommitmentProposal.validate_evidence(proposal.status, attrs)),
         :ok <- require_current_source(proposal, context),
         {:ok, evidence} <-
           Evidence.get_verified_candidate(
             command.evidence_id,
             "purchase_commitment_proposal",
             proposal.id,
             context
           ),
         {:ok, updated} <-
           Support.write(store.update(proposal, evidence_changes(evidence), context)),
         {:ok, task} <- open_task(updated, command.reason, context) do
      response = Support.proposal_view(updated) |> Map.put("review_task", task)

      audits = [
        Support.audit(updated, "purchase_commitment_proposal_submitted", command.reason),
        Support.task_audit(task, "open", command.reason)
      ]

      events = [
        Support.event(updated, "purchase_commitment_proposal_submitted"),
        Support.task_event(task, "opened")
      ]

      {:ok, response, audits, events}
    end
  end

  defp decision_operation(store, id, task_id, attrs, version, context) do
    with {:ok, proposal} <- fetch_locked(store, id, context),
         :ok <- Support.require_version(proposal, version),
         {:ok, command} <-
           Support.validate(CommitmentProposal.validate_decision(proposal.status, attrs)),
         :ok <- require_source_for_approval(proposal, command, context),
         {:ok, task} <- complete_task(task_id, proposal, command, context),
         {:ok, updated} <- update_decision(store, proposal, command, context) do
      response = Support.proposal_view(updated) |> Map.put("review_task", task)
      lifecycle = if command.decision == "approve", do: "approved", else: "held"

      audits = [
        Support.audit(updated, "purchase_commitment_proposal_#{lifecycle}", command.reason),
        Support.task_audit(task, "complete", command.reason)
      ]

      events = [
        Support.event(updated, "purchase_commitment_proposal_#{lifecycle}"),
        Support.task_event(task, "completed")
      ]

      {:ok, response, audits, events}
    end
  end

  defp persist_create(store, command, source, context) do
    attrs = %{
      tenant_id: context.tenant_id,
      stable_identifier: command.stable_identifier,
      quote_comparison_id: source["quote_comparison_id"],
      quote_comparison_version: source["quote_comparison_version"],
      selected_quote_id: source["selected_quote_id"],
      selected_quote_version: source["selected_quote_version"],
      source_snapshot: source,
      proposed_by_actor_id: context.actor_id
    }

    Support.write(store.create(attrs, context))
  end

  defp fetch_locked(store, id, context) do
    store.fetch(id, context.tenant_id, context, lock: true) |> Support.fetch()
  end

  defp require_current_source(proposal, context) do
    with {:ok, source} <-
           Sourcing.require_commitment_source(
             proposal.quote_comparison_id,
             proposal.quote_comparison_version,
             context
           ) do
      if source == proposal.source_snapshot,
        do: :ok,
        else: Support.conflict("commitment proposal source changed after creation")
    end
  end

  defp require_source_for_approval(proposal, %{decision: "approve"}, context),
    do: require_current_source(proposal, context)

  defp require_source_for_approval(_proposal, %{decision: "hold"}, _context), do: :ok

  defp evidence_changes(evidence) do
    %{
      status: "awaiting_review",
      submitted_at: DateTime.utc_now(),
      evidence_metadata: %{
        "evidence_id" => evidence["id"],
        "sha256" => evidence["sha256"],
        "classification" => evidence["classification"]
      }
    }
  end

  defp open_task(proposal, reason, context) do
    Workflow.open_human_task(
      %{
        task_kind: @task_kind,
        subject_type: "purchase_commitment_proposal",
        subject_id: proposal.id,
        subject_version: proposal.lock_version,
        required_permission: @approve_permission,
        reason: reason
      },
      context
    )
  end

  defp complete_task(task_id, proposal, command, context) do
    Workflow.complete_human_task(
      task_id,
      %{
        subject_type: "purchase_commitment_proposal",
        subject_id: proposal.id,
        subject_version: proposal.lock_version,
        resolution: command.decision,
        reason: command.reason
      },
      context
    )
  end

  defp update_decision(store, proposal, command, context) do
    attrs = %{
      status: if(command.decision == "approve", do: "approved", else: "hold"),
      decision_reason: command.reason,
      decision_actor_id: context.actor_id,
      decided_at: DateTime.utc_now()
    }

    Support.write(store.update(proposal, attrs, context))
  end

  defp task_id(attrs) when is_map(attrs) do
    Support.cast_uuid(Map.get(attrs, "task_id", Map.get(attrs, :task_id)), :task_id)
  end

  defp task_id(_attrs), do: Support.validation(%{task_id: ["must be a UUID"]})
  defp state_validation(:ok), do: :ok
  defp state_validation({:error, details}), do: Support.validation(details)
end
