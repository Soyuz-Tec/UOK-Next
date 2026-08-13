defmodule UokNext.Modules.Trade.Sourcing.Application.Rfqs do
  @moduledoc false

  alias UokNext.Kernel.{CommandTransaction, TenantTransaction}
  alias UokNext.Modules.Master.Parties.Public, as: Parties
  alias UokNext.Modules.Trade.Sourcing.Application.ProcurementSupport, as: Support
  alias UokNext.Modules.Trade.Sourcing.Domain.ProcurementRules

  @create_permission "sourcing:rfqs:create"
  @read_permission "sourcing:rfqs:read"

  def create(store, attrs, expected_version, context, key) do
    with :ok <- Support.authorize(context, @create_permission),
         {:ok, version} <- Support.cast_version(expected_version),
         {:ok, command} <- Support.validate(ProcurementRules.validate_rfq(attrs)) do
      payload =
        command |> Map.put(:tenant_id, context.tenant_id) |> Map.put(:expected_version, version)

      CommandTransaction.execute(context, "trade.sourcing.create_rfq", key, payload, fn ->
        create_operation(store, command, version, context)
      end)
    end
  end

  def list(store, limit, context) when is_integer(limit) and limit in 1..100 do
    with :ok <- Support.authorize(context, @read_permission) do
      TenantTransaction.run(context, fn ->
        records =
          store.list_rfqs(context.tenant_id, limit, context)
          |> Enum.map(&rfq_view_with_suppliers(store, &1, context))

        {:ok, records}
      end)
    end
  end

  def list(_store, _limit, _context), do: Support.validation(%{limit: ["must be 1 to 100"]})

  defp create_operation(store, command, version, context) do
    with {:ok, requisition} <-
           Support.fetch(
             store.fetch_requisition(command.requisition_id, context.tenant_id, context,
               lock: true
             )
           ),
         :ok <- Support.require_version(requisition, version),
         :ok <- require_ready(requisition),
         {:ok, suppliers} <- approved_suppliers(command.supplier_party_ids, context),
         {:ok, updated_requisition} <-
           Support.write(store.update_requisition(requisition, %{status: "rfq_open"}, context)),
         {:ok, rfq} <- persist(store, command, suppliers, updated_requisition, context) do
      response =
        Support.rfq_view(rfq) |> Map.put("supplier_party_ids", command.supplier_party_ids)

      audits = [
        Support.audit(
          "purchase_requisition",
          updated_requisition,
          "requisition_opened_for_rfq",
          command.reason
        ),
        Support.audit("rfq", rfq, "rfq_created", command.reason)
      ]

      events = [
        Support.event("purchase_requisition", updated_requisition, "requisition_opened_for_rfq"),
        Support.event("rfq", rfq, "rfq_created")
      ]

      {:ok, response, audits, events}
    end
  end

  defp approved_suppliers(ids, context) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      case Parties.require_approved(id, context) do
        {:ok, party} ->
          supplier = %{supplier_party_id: id, supplier_party_version: party["lock_version"]}
          {:cont, {:ok, [supplier | acc]}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, suppliers} -> {:ok, Enum.reverse(suppliers)}
      error -> error
    end
  end

  defp persist(store, command, suppliers, requisition, context) do
    attrs =
      command
      |> Map.drop([:reason, :supplier_party_ids])
      |> Map.put(:tenant_id, context.tenant_id)
      |> Map.put(:requisition_version, requisition.lock_version)

    Support.write(store.create_rfq(attrs, suppliers, context))
  end

  defp rfq_view_with_suppliers(store, rfq, context) do
    supplier_ids = store.rfq_supplier_ids(rfq.id, context.tenant_id, context)
    Support.rfq_view(rfq) |> Map.put("supplier_party_ids", supplier_ids)
  end

  defp require_ready(%{status: "ready_for_rfq"}), do: :ok
  defp require_ready(_record), do: Support.conflict("requisition is not ready for an RFQ")
end
