defmodule UokNext.Modules.Trade.Sourcing.Application.QuoteComparisons do
  @moduledoc false

  alias UokNext.Kernel.{CommandTransaction, TenantTransaction}
  alias UokNext.Modules.Platform.Workflow.Public, as: Workflow
  alias UokNext.Modules.Trade.Sourcing.Application.ProcurementSupport, as: Support
  alias UokNext.Modules.Trade.Sourcing.Domain.ProcurementRules

  @create_permission "sourcing:comparisons:create"
  @read_permission "sourcing:comparisons:read"
  @approve_permission "sourcing:comparisons:approve"
  @task_kind "trade.sourcing.quote_comparison_review"

  def create(store, attrs, expected_version, context, key) do
    with :ok <- Support.authorize(context, @create_permission),
         {:ok, version} <- Support.cast_version(expected_version),
         {:ok, command} <- Support.validate(ProcurementRules.validate_comparison(attrs)) do
      payload =
        command |> Map.put(:tenant_id, context.tenant_id) |> Map.put(:expected_version, version)

      CommandTransaction.execute(
        context,
        "trade.sourcing.create_quote_comparison",
        key,
        payload,
        fn ->
          create_operation(store, command, version, context)
        end
      )
    end
  end

  def decide(store, comparison_id, attrs, expected_version, context, key) do
    with :ok <- Support.authorize(context, @approve_permission),
         {:ok, id} <- Support.cast_uuid(comparison_id, :comparison_id),
         {:ok, task_id} <- task_id(attrs),
         {:ok, version} <- Support.cast_version(expected_version) do
      payload = %{comparison_id: id, task_id: task_id, expected_version: version, decision: attrs}

      CommandTransaction.execute(
        context,
        "trade.sourcing.decide_quote_comparison",
        key,
        payload,
        fn ->
          decision_operation(store, id, task_id, attrs, version, context)
        end
      )
    end
  end

  def list(store, limit, context) when is_integer(limit) and limit in 1..100 do
    with :ok <- Support.authorize(context, @read_permission) do
      TenantTransaction.run(context, fn ->
        {:ok,
         store.list_comparisons(context.tenant_id, limit, context)
         |> Enum.map(&Support.comparison_view/1)}
      end)
    end
  end

  def list(_store, _limit, _context), do: Support.validation(%{limit: ["must be 1 to 100"]})

  defp create_operation(store, command, version, context) do
    with {:ok, rfq} <-
           Support.fetch(store.fetch_rfq(command.rfq_id, context.tenant_id, context, lock: true)),
         :ok <- Support.require_version(rfq, version),
         :ok <- require_open(rfq),
         {:ok, ranking} <- rank_submitted_quotes(store, rfq, context),
         {:ok, pending_rfq} <-
           Support.write(store.update_rfq(rfq, %{status: "comparison_pending"}, context)),
         {:ok, comparison} <- persist(store, command, ranking, pending_rfq, context),
         {:ok, task} <- open_task(comparison, command.reason, context) do
      response = Support.comparison_view(comparison) |> Map.put("review_task", task)

      audits = [
        Support.audit("rfq", pending_rfq, "rfq_closed_for_comparison", command.reason),
        Support.audit("quote_comparison", comparison, "quote_comparison_created", command.reason),
        Support.task_audit(task, "open", command.reason)
      ]

      events = [
        Support.event("rfq", pending_rfq, "rfq_closed_for_comparison"),
        Support.event("quote_comparison", comparison, "quote_comparison_created"),
        Support.task_event(task, "opened")
      ]

      {:ok, response, audits, events}
    end
  end

  defp decision_operation(store, id, task_id, attrs, version, context) do
    with {:ok, comparison} <-
           Support.fetch(store.fetch_comparison(id, context.tenant_id, context, lock: true)),
         :ok <- Support.require_version(comparison, version),
         {:ok, command} <-
           Support.validate(ProcurementRules.validate_decision(comparison.status, attrs)),
         {:ok, rfq} <-
           Support.fetch(
             store.fetch_rfq(comparison.rfq_id, context.tenant_id, context, lock: true)
           ),
         :ok <- Support.require_version(rfq, comparison.rfq_version),
         {:ok, task} <- complete_task(task_id, comparison, command, context),
         {:ok, updated_comparison} <- update_comparison(store, comparison, command, context),
         {:ok, updated_rfq} <- update_rfq(store, rfq, command, context) do
      response = Support.comparison_view(updated_comparison) |> Map.put("review_task", task)

      lifecycle =
        if command.decision == "approve",
          do: "quote_comparison_approved",
          else: "quote_comparison_held"

      audits = [
        Support.audit("quote_comparison", updated_comparison, lifecycle, command.reason),
        Support.audit("rfq", updated_rfq, "rfq_comparison_decided", command.reason),
        Support.task_audit(task, "complete", command.reason)
      ]

      events = [
        Support.event("quote_comparison", updated_comparison, lifecycle),
        Support.event("rfq", updated_rfq, "rfq_comparison_decided"),
        Support.task_event(task, "completed")
      ]

      {:ok, response, audits, events}
    end
  end

  defp rank_submitted_quotes(store, rfq, context) do
    quotes =
      store.list_quotes(context.tenant_id, rfq.id, 100, context)
      |> Enum.filter(&(&1.status == "submitted"))
      |> Enum.sort(&rank_before?/2)

    invited_count =
      store.rfq_supplier_ids(rfq.id, context.tenant_id, context)
      |> length()

    with :ok <- require_minimum_quotes(quotes),
         :ok <- require_fair_close(rfq, quotes, invited_count) do
      {:ok, Enum.map(quotes, &ranking_row/1)}
    end
  end

  defp require_minimum_quotes(quotes) when length(quotes) >= 2, do: :ok

  defp require_minimum_quotes(_quotes),
    do: Support.conflict("at least two submitted quotes are required")

  defp require_fair_close(_rfq, quotes, invited_count) when length(quotes) == invited_count,
    do: :ok

  defp require_fair_close(%{response_deadline: deadline}, _quotes, _invited_count) do
    if DateTime.compare(deadline, DateTime.utc_now()) in [:lt, :eq],
      do: :ok,
      else: Support.conflict("all invited suppliers must submit before an early comparison")
  end

  defp rank_before?(left, right) do
    case Decimal.compare(total(left), total(right)) do
      :lt ->
        true

      :gt ->
        false

      :eq ->
        {left.delivery_days, left.stable_identifier} <=
          {right.delivery_days, right.stable_identifier}
    end
  end

  defp total(quote), do: Decimal.mult(quote.quoted_quantity, quote.unit_price)

  defp ranking_row(quote) do
    %{
      "quote_id" => quote.id,
      "supplier_party_id" => quote.supplier_party_id,
      "quote_version" => quote.lock_version,
      "quoted_quantity" => Decimal.to_string(quote.quoted_quantity, :normal),
      "unit_price" => Decimal.to_string(quote.unit_price, :normal),
      "total_price" => total(quote) |> Decimal.to_string(:normal),
      "currency_code" => quote.currency_code,
      "delivery_days" => quote.delivery_days
    }
  end

  defp persist(store, command, ranking, rfq, context) do
    attrs = %{
      tenant_id: context.tenant_id,
      stable_identifier: command.stable_identifier,
      rfq_id: rfq.id,
      rfq_version: rfq.lock_version,
      recommended_quote_id: ranking |> hd() |> Map.fetch!("quote_id"),
      ranking_snapshot: %{"formula_version" => 1, "ranking" => ranking}
    }

    Support.write(store.create_comparison(attrs, context))
  end

  defp open_task(comparison, reason, context) do
    Workflow.open_human_task(
      %{
        task_kind: @task_kind,
        subject_type: "quote_comparison",
        subject_id: comparison.id,
        subject_version: comparison.lock_version,
        required_permission: @approve_permission,
        reason: reason
      },
      context
    )
  end

  defp complete_task(task_id, comparison, command, context) do
    Workflow.complete_human_task(
      task_id,
      %{
        subject_type: "quote_comparison",
        subject_id: comparison.id,
        subject_version: comparison.lock_version,
        resolution: command.decision,
        reason: command.reason
      },
      context
    )
  end

  defp update_comparison(store, comparison, command, context) do
    attrs = %{
      status: if(command.decision == "approve", do: "approved", else: "hold"),
      decision_reason: command.reason,
      decision_actor_id: context.actor_id,
      decided_at: DateTime.utc_now()
    }

    Support.write(store.update_comparison(comparison, attrs, context))
  end

  defp update_rfq(store, rfq, command, context) do
    status = if command.decision == "approve", do: "compared", else: "hold"
    Support.write(store.update_rfq(rfq, %{status: status}, context))
  end

  defp require_open(%{status: "open"}), do: :ok
  defp require_open(_rfq), do: Support.conflict("RFQ is not open for comparison")

  defp task_id(attrs) when is_map(attrs) do
    Support.cast_uuid(Map.get(attrs, "task_id", Map.get(attrs, :task_id)), :task_id)
  end

  defp task_id(_attrs), do: Support.validation(%{task_id: ["must be a UUID"]})
end
