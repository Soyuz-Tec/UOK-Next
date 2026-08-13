defmodule UokNext.Modules.Trade.Sourcing.Infrastructure.EctoProcurementStore do
  @moduledoc false
  @behaviour UokNext.Modules.Trade.Sourcing.Application.ProcurementStore

  import Ecto.Query

  alias UokNext.Modules.Trade.Sourcing.Infrastructure.{
    PurchaseRequisitionRecord,
    QuoteComparisonRecord,
    RfqRecord,
    RfqSupplierRecord,
    SupplierQuoteRecord
  }

  alias UokNext.Repo

  def create_requisition(attrs, _context),
    do: insert(PurchaseRequisitionRecord, :create_changeset, attrs)

  def fetch_requisition(id, tenant_id, _context, options),
    do: fetch(PurchaseRequisitionRecord, id, tenant_id, options)

  def list_requisitions(tenant_id, limit, _context),
    do: list(PurchaseRequisitionRecord, tenant_id, limit)

  def update_requisition(record, attrs, _context),
    do: persist_update(record, PurchaseRequisitionRecord, attrs)

  def create_rfq(attrs, suppliers, _context) do
    with {:ok, rfq} <- insert(RfqRecord, :create_changeset, attrs),
         :ok <- insert_suppliers(rfq, suppliers) do
      {:ok, rfq}
    end
  end

  def fetch_rfq(id, tenant_id, _context, options), do: fetch(RfqRecord, id, tenant_id, options)
  def list_rfqs(tenant_id, limit, _context), do: list(RfqRecord, tenant_id, limit)

  def rfq_supplier_ids(rfq_id, tenant_id, _context) do
    from(invitation in RfqSupplierRecord,
      where: invitation.tenant_id == ^tenant_id and invitation.rfq_id == ^rfq_id,
      order_by: [asc: invitation.supplier_party_id],
      select: invitation.supplier_party_id
    )
    |> Repo.all()
  end

  def update_rfq(record, attrs, _context), do: persist_update(record, RfqRecord, attrs)

  def invited_supplier?(rfq_id, supplier_id, tenant_id, _context) do
    Repo.exists?(
      from invitation in RfqSupplierRecord,
        where:
          invitation.tenant_id == ^tenant_id and invitation.rfq_id == ^rfq_id and
            invitation.supplier_party_id == ^supplier_id
    )
  end

  def create_quote(attrs, _context), do: insert(SupplierQuoteRecord, :create_changeset, attrs)

  def fetch_quote(id, tenant_id, _context, options),
    do: fetch(SupplierQuoteRecord, id, tenant_id, options)

  def list_quotes(tenant_id, rfq_id, limit, _context) do
    SupplierQuoteRecord
    |> list_query(tenant_id, limit)
    |> maybe_filter_rfq(rfq_id)
    |> Repo.all()
  end

  def update_quote(record, attrs, _context),
    do: persist_update(record, SupplierQuoteRecord, attrs)

  def create_comparison(attrs, _context),
    do: insert(QuoteComparisonRecord, :create_changeset, attrs)

  def fetch_comparison(id, tenant_id, _context, options),
    do: fetch(QuoteComparisonRecord, id, tenant_id, options)

  def list_comparisons(tenant_id, limit, _context),
    do: list(QuoteComparisonRecord, tenant_id, limit)

  def update_comparison(record, attrs, _context),
    do: persist_update(record, QuoteComparisonRecord, attrs)

  defp insert_suppliers(rfq, suppliers) do
    Enum.reduce_while(suppliers, :ok, fn supplier, :ok ->
      attrs =
        supplier
        |> Map.put(:tenant_id, rfq.tenant_id)
        |> Map.put(:rfq_id, rfq.id)

      case insert(RfqSupplierRecord, :create_changeset, attrs) do
        {:ok, _record} -> {:cont, :ok}
        {:error, details} -> {:halt, {:error, details}}
      end
    end)
  end

  defp insert(schema, changeset_function, attrs) do
    schema.__struct__()
    |> apply(schema, changeset_function, attrs)
    |> Repo.insert()
    |> normalize_write()
  end

  defp apply(record, schema, changeset_function, attrs),
    do: Kernel.apply(schema, changeset_function, [record, attrs])

  defp fetch(schema, id, tenant_id, options) do
    query = from record in schema, where: record.id == ^id and record.tenant_id == ^tenant_id
    query = if Keyword.get(options, :lock, false), do: lock(query, "FOR UPDATE"), else: query
    query |> Repo.one() |> normalize_fetch()
  end

  defp list(schema, tenant_id, limit), do: schema |> list_query(tenant_id, limit) |> Repo.all()

  defp list_query(schema, tenant_id, limit) do
    from record in schema,
      where: record.tenant_id == ^tenant_id,
      order_by: [desc: record.inserted_at, desc: record.id],
      limit: ^limit
  end

  defp maybe_filter_rfq(query, nil), do: query
  defp maybe_filter_rfq(query, rfq_id), do: from(record in query, where: record.rfq_id == ^rfq_id)

  defp persist_update(record, schema, attrs) do
    record
    |> apply(schema, :transition_changeset, attrs)
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
