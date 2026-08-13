defmodule UokNext.Modules.Trade.Sourcing.Application.Requisitions do
  @moduledoc false

  alias UokNext.Kernel.{CommandTransaction, TenantTransaction}
  alias UokNext.Modules.Master.Products.Public, as: Products
  alias UokNext.Modules.Trade.Sourcing.Application.ProcurementSupport, as: Support
  alias UokNext.Modules.Trade.Sourcing.Domain.ProcurementRules
  alias UokNext.Modules.Trade.Sourcing.Public, as: Sourcing

  @create_permission "sourcing:requisitions:create"
  @read_permission "sourcing:requisitions:read"

  def create(store, attrs, context, key) do
    with :ok <- Support.authorize(context, @create_permission),
         {:ok, command} <- Support.validate(ProcurementRules.validate_requisition(attrs)) do
      payload = Map.put(command, :tenant_id, context.tenant_id)

      CommandTransaction.execute(context, "trade.sourcing.create_requisition", key, payload, fn ->
        create_operation(store, command, context)
      end)
    end
  end

  def list(store, limit, context) when is_integer(limit) and limit in 1..100 do
    with :ok <- Support.authorize(context, @read_permission) do
      TenantTransaction.run(context, fn ->
        {:ok,
         store.list_requisitions(context.tenant_id, limit, context)
         |> Enum.map(&Support.requisition_view/1)}
      end)
    end
  end

  def list(_store, _limit, _context), do: Support.validation(%{limit: ["must be 1 to 100"]})

  defp create_operation(store, command, context) do
    with {:ok, lane} <- Sourcing.get(command.sourcing_lane_id, context),
         :ok <- require_approved_lane(lane),
         {:ok, product} <- Products.require_active(lane["product_id"], context),
         :ok <- require_unit(product, command.unit_code),
         {:ok, record} <- persist(store, command, lane, context) do
      {:ok, Support.requisition_view(record),
       Support.audit("purchase_requisition", record, "requisition_created", command.reason),
       [Support.event("purchase_requisition", record, "requisition_created")]}
    end
  end

  defp persist(store, command, lane, context) do
    attrs =
      command
      |> Map.delete(:reason)
      |> Map.put(:tenant_id, context.tenant_id)
      |> Map.put(:sourcing_lane_version, lane["lock_version"])

    Support.write(store.create_requisition(attrs, context))
  end

  defp require_approved_lane(%{"status" => "approved"}), do: :ok
  defp require_approved_lane(_lane), do: Support.not_found()

  defp require_unit(%{"base_unit_code" => unit}, unit), do: :ok

  defp require_unit(_product, _unit),
    do: Support.validation(%{unit_code: ["must match product base unit"]})
end
