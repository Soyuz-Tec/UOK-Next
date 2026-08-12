defmodule UokNext.Modules.Platform.Integrations.Infrastructure.EctoConnectorReceiptStore do
  @moduledoc false

  @behaviour UokNext.Modules.Platform.Integrations.Application.ConnectorReceiptStore

  import Ecto.Query

  alias UokNext.Modules.Platform.Integrations.Infrastructure.ConnectorReceiptRecord
  alias UokNext.Repo

  @impl true
  def create(attrs, _context) do
    %ConnectorReceiptRecord{}
    |> ConnectorReceiptRecord.create_changeset(attrs)
    |> Repo.insert()
    |> normalize_write()
  end

  @impl true
  def fetch(id, tenant_id, _context) do
    id
    |> scoped_query(tenant_id)
    |> Repo.one()
    |> normalize_fetch()
  end

  @impl true
  def fetch_for_update(id, tenant_id, _context) do
    id
    |> scoped_query(tenant_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> normalize_fetch()
  end

  @impl true
  def reconcile(record, attrs, _context) do
    record
    |> ConnectorReceiptRecord.reconciliation_changeset(attrs)
    |> Repo.update(stale_error_field: :lock_version, stale_error_message: "is stale")
    |> normalize_update()
  end

  defp scoped_query(id, tenant_id) do
    from(receipt in ConnectorReceiptRecord,
      where: receipt.id == ^id and receipt.tenant_id == ^tenant_id
    )
  end

  defp normalize_fetch(nil), do: :not_found
  defp normalize_fetch(record), do: {:ok, record}
  defp normalize_write({:ok, record}), do: {:ok, record}
  defp normalize_write({:error, changeset}), do: {:error, changeset_errors(changeset)}
  defp normalize_update({:ok, record}), do: {:ok, record}

  defp normalize_update({:error, changeset}) do
    if Keyword.has_key?(changeset.errors, :lock_version),
      do: {:error, :stale},
      else: {:error, changeset_errors(changeset)}
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, rendered ->
        String.replace(rendered, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
