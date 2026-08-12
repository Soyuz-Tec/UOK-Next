defmodule UokNext.Modules.Master.Products.Application.Products do
  @moduledoc false

  alias UokNext.Kernel.{CommandContext, CommandError, CommandTransaction, TenantTransaction}
  alias UokNext.Modules.Master.Products.Domain.Product
  alias UokNext.Modules.Master.Products.Policies.Authorization

  @create_permission "products:create"
  @read_permission "products:read"

  @spec create(module(), map(), CommandContext.t(), String.t()) :: tuple()
  def create(store, attrs, context, idempotency_key) do
    with :ok <- Authorization.require_permission(context, @create_permission),
         {:ok, command} <- validate(Product.validate_create(attrs)) do
      payload = Map.put(command, :tenant_id, context.tenant_id)

      CommandTransaction.execute(
        context,
        "master.products.create",
        idempotency_key,
        payload,
        fn -> create_operation(store, command, context) end
      )
    end
  end

  @spec get(module(), String.t(), CommandContext.t()) :: tuple()
  def get(store, product_id, context) do
    with :ok <- Authorization.require_permission(context, @read_permission),
         {:ok, id} <- cast_uuid(product_id) do
      TenantTransaction.run(context, fn -> fetch_view(store, id, context) end)
    end
  end

  @spec require_active(module(), String.t(), CommandContext.t()) :: tuple()
  def require_active(store, product_id, context) do
    with {:ok, product} <- get(store, product_id, context),
         true <- product["status"] == "active" do
      {:ok, product}
    else
      false -> not_found()
      {:error, %CommandError{} = error} -> {:error, error}
    end
  end

  @spec list(module(), pos_integer(), CommandContext.t()) :: tuple()
  def list(store, limit, context) when is_integer(limit) and limit in 1..100 do
    with :ok <- Authorization.require_permission(context, @read_permission) do
      TenantTransaction.run(context, fn ->
        {:ok, store.list(context.tenant_id, limit, context) |> Enum.map(&view/1)}
      end)
    end
  end

  def list(_store, _limit, _context), do: validation_error(%{limit: ["must be 1 to 100"]})

  defp create_operation(store, command, context) do
    attrs = command |> Map.delete(:reason) |> Map.put(:tenant_id, context.tenant_id)

    case store.create(attrs, context) do
      {:ok, product} ->
        {:ok, view(product), audit(product, command.reason), [event(product)]}

      {:error, details} ->
        validation_error(details)
    end
  end

  defp fetch_view(store, id, context) do
    case store.fetch(id, context.tenant_id, context) do
      {:ok, product} -> {:ok, view(product)}
      :not_found -> not_found()
    end
  end

  defp view(product) do
    %{
      "id" => product.id,
      "tenant_id" => product.tenant_id,
      "stable_identifier" => product.stable_identifier,
      "name" => product.name,
      "product_kind" => product.product_kind,
      "base_unit_code" => product.base_unit_code,
      "status" => product.status,
      "lock_version" => product.lock_version
    }
  end

  defp audit(product, reason) do
    %{
      action: "master.products.create",
      resource_type: "product",
      resource_id: product.id,
      reason: reason,
      classification: "internal",
      metadata: %{"status" => product.status, "aggregate_version" => product.lock_version}
    }
  end

  defp event(product) do
    %{
      name: "master.products.product_created",
      aggregate_type: "product",
      aggregate_id: product.id,
      aggregate_version: product.lock_version,
      classification: "internal",
      payload: %{"product_id" => product.id, "status" => product.status}
    }
  end

  defp cast_uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> validation_error(%{product_id: ["must be a UUID"]})
    end
  end

  defp validate({:ok, value}), do: {:ok, value}
  defp validate({:error, details}), do: validation_error(details)

  defp validation_error(details),
    do: {:error, CommandError.new("validation_failed", "product validation failed", 422, details)}

  defp not_found, do: {:error, CommandError.new("not_found", "record was not found", 404)}
end
