defmodule UokNext.Modules.Master.Products.Public do
  @moduledoc "Supported command and query boundary for `master.products`."

  alias UokNext.Modules.Master.Products.Application.Products
  alias UokNext.Modules.Master.Products.Infrastructure.EctoProductStore

  @spec create(map(), UokNext.Kernel.CommandContext.t(), String.t()) :: tuple()
  def create(attrs, context, idempotency_key),
    do: Products.create(EctoProductStore, attrs, context, idempotency_key)

  @spec get(String.t(), UokNext.Kernel.CommandContext.t()) :: tuple()
  def get(product_id, context), do: Products.get(EctoProductStore, product_id, context)

  @spec require_active(String.t(), UokNext.Kernel.CommandContext.t()) :: tuple()
  def require_active(product_id, context),
    do: Products.require_active(EctoProductStore, product_id, context)

  @spec list(pos_integer(), UokNext.Kernel.CommandContext.t()) :: tuple()
  def list(limit, context), do: Products.list(EctoProductStore, limit, context)
end
