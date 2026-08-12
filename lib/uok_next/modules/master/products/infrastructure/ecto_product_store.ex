defmodule UokNext.Modules.Master.Products.Infrastructure.EctoProductStore do
  @moduledoc false

  @behaviour UokNext.Modules.Master.Products.Application.ProductStore

  import Ecto.Query

  alias UokNext.Modules.Master.Products.Infrastructure.ProductRecord
  alias UokNext.Repo

  @impl true
  def create(attrs, _context) do
    %ProductRecord{}
    |> ProductRecord.create_changeset(attrs)
    |> Repo.insert()
    |> normalize_write()
  end

  @impl true
  def fetch(id, tenant_id, _context) do
    from(product in ProductRecord,
      where: product.id == ^id and product.tenant_id == ^tenant_id
    )
    |> Repo.one()
    |> normalize_fetch()
  end

  @impl true
  def list(tenant_id, limit, _context) do
    from(product in ProductRecord,
      where: product.tenant_id == ^tenant_id,
      order_by: [asc: product.name, asc: product.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp normalize_fetch(nil), do: :not_found
  defp normalize_fetch(record), do: {:ok, record}
  defp normalize_write({:ok, record}), do: {:ok, record}

  defp normalize_write({:error, changeset}) do
    {:error,
     Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
       Enum.reduce(options, message, fn {key, value}, rendered ->
         String.replace(rendered, "%{#{key}}", to_string(value))
       end)
     end)}
  end
end
