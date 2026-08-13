defmodule UokNext.Modules.Trade.Sourcing.Application.SupplierQuotes do
  @moduledoc false

  alias UokNext.Kernel.{CommandTransaction, TenantTransaction}
  alias UokNext.Modules.Master.Parties.Public, as: Parties
  alias UokNext.Modules.Platform.Evidence.Public, as: Evidence
  alias UokNext.Modules.Trade.Sourcing.Application.ProcurementSupport, as: Support
  alias UokNext.Modules.Trade.Sourcing.Domain.ProcurementRules

  @create_permission "sourcing:quotes:create"
  @read_permission "sourcing:quotes:read"
  @evidence_permission "sourcing:quotes:evidence:submit"

  def create(store, attrs, context, key) do
    with :ok <- Support.authorize(context, @create_permission),
         {:ok, command} <- Support.validate(ProcurementRules.validate_quote(attrs)) do
      payload = Map.put(command, :tenant_id, context.tenant_id)

      CommandTransaction.execute(
        context,
        "trade.sourcing.create_supplier_quote",
        key,
        payload,
        fn ->
          create_operation(store, command, context)
        end
      )
    end
  end

  def preflight_evidence(store, quote_id, expected_version, context) do
    with :ok <- Support.authorize(context, @evidence_permission),
         {:ok, id} <- Support.cast_uuid(quote_id, :quote_id),
         {:ok, version} <- Support.cast_version(expected_version) do
      TenantTransaction.run(context, fn -> preflight_scoped(store, id, version, context) end)
    end
  end

  def submit_evidence(store, quote_id, attrs, expected_version, context, key) do
    with :ok <- Support.authorize(context, @evidence_permission),
         {:ok, id} <- Support.cast_uuid(quote_id, :quote_id),
         {:ok, version} <- Support.cast_version(expected_version) do
      payload = %{quote_id: id, expected_version: version, evidence: attrs}

      CommandTransaction.execute(
        context,
        "trade.sourcing.submit_quote_evidence",
        key,
        payload,
        fn ->
          evidence_operation(store, id, attrs, version, context)
        end
      )
    end
  end

  def list(store, rfq_id, limit, context) when is_integer(limit) and limit in 1..100 do
    with :ok <- Support.authorize(context, @read_permission),
         {:ok, filter_id} <- optional_uuid(rfq_id) do
      TenantTransaction.run(context, fn ->
        {:ok,
         store.list_quotes(context.tenant_id, filter_id, limit, context)
         |> Enum.map(&Support.quote_view/1)}
      end)
    end
  end

  def list(_store, _rfq_id, _limit, _context),
    do: Support.validation(%{limit: ["must be 1 to 100"]})

  defp create_operation(store, command, context) do
    with {:ok, rfq} <-
           Support.fetch(store.fetch_rfq(command.rfq_id, context.tenant_id, context, lock: true)),
         :ok <- require_open_rfq(rfq),
         {:ok, requisition} <-
           Support.fetch(
             store.fetch_requisition(rfq.requisition_id, context.tenant_id, context, [])
           ),
         :ok <- Support.require_version(requisition, rfq.requisition_version),
         :ok <- require_quote_terms(command, rfq, requisition),
         {:ok, _party} <- Parties.require_approved(command.supplier_party_id, context),
         true <-
           store.invited_supplier?(rfq.id, command.supplier_party_id, context.tenant_id, context) ||
             Support.not_found(),
         {:ok, quote} <- persist(store, command, context) do
      {:ok, Support.quote_view(quote),
       Support.audit("supplier_quote", quote, "supplier_quote_created", command.reason),
       [Support.event("supplier_quote", quote, "supplier_quote_created")]}
    end
  end

  defp preflight_scoped(store, id, version, context) do
    with {:ok, quote} <- Support.fetch(store.fetch_quote(id, context.tenant_id, context, [])),
         :ok <- Support.require_version(quote, version) do
      state_validation(ProcurementRules.validate_quote_evidence_state(quote.status))
    end
  end

  defp evidence_operation(store, id, attrs, version, context) do
    with {:ok, quote} <-
           Support.fetch(store.fetch_quote(id, context.tenant_id, context, lock: true)),
         :ok <- Support.require_version(quote, version),
         {:ok, rfq} <-
           Support.fetch(store.fetch_rfq(quote.rfq_id, context.tenant_id, context, lock: true)),
         :ok <- require_open_rfq(rfq),
         {:ok, command} <-
           Support.validate(ProcurementRules.validate_quote_evidence(quote.status, attrs)),
         {:ok, evidence} <-
           Evidence.get_verified_candidate(
             command.evidence_id,
             "supplier_quote",
             quote.id,
             context
           ),
         {:ok, updated} <-
           Support.write(store.update_quote(quote, evidence_changes(evidence), context)) do
      {:ok, Support.quote_view(updated),
       Support.audit("supplier_quote", updated, "supplier_quote_submitted", command.reason),
       [Support.event("supplier_quote", updated, "supplier_quote_submitted")]}
    end
  end

  defp persist(store, command, context) do
    attrs = command |> Map.delete(:reason) |> Map.put(:tenant_id, context.tenant_id)
    Support.write(store.create_quote(attrs, context))
  end

  defp evidence_changes(evidence) do
    %{
      status: "submitted",
      submitted_at: DateTime.utc_now(),
      evidence_metadata: %{
        "evidence_id" => evidence["id"],
        "sha256" => evidence["sha256"],
        "classification" => evidence["classification"]
      }
    }
  end

  defp require_quote_terms(command, rfq, requisition) do
    cond do
      command.currency_code != rfq.settlement_currency_code ->
        Support.validation(%{currency_code: ["must match the RFQ settlement currency"]})

      not Decimal.equal?(command.quoted_quantity, requisition.quantity) ->
        Support.validation(%{quoted_quantity: ["must match the requisition quantity"]})

      true ->
        :ok
    end
  end

  defp require_open_rfq(%{status: "open", response_deadline: deadline}) do
    if DateTime.compare(deadline, DateTime.utc_now()) == :gt,
      do: :ok,
      else: Support.conflict("RFQ response deadline has passed")
  end

  defp require_open_rfq(_rfq), do: Support.conflict("RFQ is not accepting quotes")
  defp optional_uuid(nil), do: {:ok, nil}
  defp optional_uuid(""), do: {:ok, nil}
  defp optional_uuid(value), do: Support.cast_uuid(value, :rfq_id)
  defp state_validation(:ok), do: :ok
  defp state_validation({:error, details}), do: Support.validation(details)
end
