defmodule UokNext.Modules.Trade.Shipments.Infrastructure.EctoReadinessStore do
  @moduledoc false

  @behaviour UokNext.Modules.Trade.Shipments.Application.ReadinessStore

  import Ecto.Query

  alias UokNext.Modules.Trade.Shipments.Infrastructure.ShipmentReadinessCaseRecord
  alias UokNext.Repo

  def create(attrs, _context) do
    %ShipmentReadinessCaseRecord{}
    |> ShipmentReadinessCaseRecord.create_changeset(attrs)
    |> Repo.insert()
    |> normalize_write()
  end

  def fetch(id, tenant_id, _context, options) do
    query =
      from readiness in ShipmentReadinessCaseRecord,
        where: readiness.id == ^id and readiness.tenant_id == ^tenant_id

    query = if Keyword.get(options, :lock, false), do: lock(query, "FOR UPDATE"), else: query
    query |> Repo.one() |> normalize_fetch()
  end

  def list(tenant_id, limit, _context) do
    from(readiness in ShipmentReadinessCaseRecord,
      where: readiness.tenant_id == ^tenant_id,
      order_by: [desc: readiness.inserted_at, desc: readiness.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  def update(record, attrs, _context) do
    record
    |> ShipmentReadinessCaseRecord.transition_changeset(attrs)
    |> Repo.update(stale_error_field: :lock_version, stale_error_message: "is stale")
    |> normalize_update()
  end

  defp normalize_fetch(nil), do: :not_found
  defp normalize_fetch(record), do: {:ok, record}
  defp normalize_write({:ok, record}), do: {:ok, record}
  defp normalize_write({:error, changeset}), do: {:error, errors(changeset)}
  defp normalize_update({:ok, record}), do: {:ok, record}

  defp normalize_update({:error, changeset}) do
    if Keyword.has_key?(changeset.errors, :lock_version),
      do: {:error, :stale},
      else: {:error, errors(changeset)}
  end

  defp errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, rendered ->
        String.replace(rendered, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
