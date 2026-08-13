defmodule UokNext.Modules.Trade.Sourcing.Application.CommitmentSources do
  @moduledoc false

  alias UokNext.Kernel.TenantTransaction
  alias UokNext.Modules.Master.Parties.Public, as: Parties
  alias UokNext.Modules.Trade.Sourcing.Application.ProcurementSupport, as: Support

  @read_permission "sourcing:comparisons:read"

  def require_current(store, comparison_id, expected_version, context) do
    with :ok <- Support.authorize(context, @read_permission),
         {:ok, id} <- Support.cast_uuid(comparison_id, :comparison_id),
         {:ok, version} <- Support.cast_version(expected_version) do
      TenantTransaction.run(context, fn -> locked_source(store, id, version, context) end)
    end
  end

  defp locked_source(store, id, version, context) do
    with {:ok, comparison} <- fetch_comparison(store, id, context),
         :ok <- Support.require_version(comparison, version),
         :ok <- require_status(comparison, "approved", "comparison is not approved"),
         {:ok, rfq} <- fetch_rfq(store, comparison.rfq_id, context),
         :ok <- require_decided_rfq_version(rfq, comparison),
         :ok <- require_status(rfq, "compared", "RFQ is not in compared state"),
         {:ok, requisition} <- fetch_requisition(store, rfq.requisition_id, context),
         :ok <- Support.require_version(requisition, rfq.requisition_version),
         {:ok, row} <- recommended_row(comparison),
         {:ok, quote} <- fetch_quote(store, comparison.recommended_quote_id, context),
         :ok <- require_status(quote, "submitted", "recommended quote is not submitted"),
         :ok <- source_versions_match(quote, row),
         :ok <- source_terms_match(quote, rfq, row),
         {:ok, _supplier} <- Parties.require_approved(quote.supplier_party_id, context) do
      {:ok, source_view(comparison, rfq, requisition, quote, row)}
    end
  end

  defp fetch_comparison(store, id, context) do
    store.fetch_comparison(id, context.tenant_id, context, lock: true) |> Support.fetch()
  end

  defp fetch_rfq(store, id, context) do
    store.fetch_rfq(id, context.tenant_id, context, lock: true) |> Support.fetch()
  end

  defp fetch_requisition(store, id, context) do
    store.fetch_requisition(id, context.tenant_id, context, lock: true) |> Support.fetch()
  end

  defp fetch_quote(store, id, context) do
    store.fetch_quote(id, context.tenant_id, context, lock: true) |> Support.fetch()
  end

  defp recommended_row(%{ranking_snapshot: %{"formula_version" => 1, "ranking" => rows}} = record)
       when is_list(rows) do
    case Enum.find(rows, &(Map.get(&1, "quote_id") == record.recommended_quote_id)) do
      nil -> integrity_conflict()
      row when is_map(row) -> {:ok, row}
    end
  end

  defp recommended_row(_record), do: integrity_conflict()

  defp source_versions_match(quote, %{"quote_version" => version})
       when is_integer(version) and quote.lock_version == version,
       do: :ok

  defp source_versions_match(_quote, _row), do: integrity_conflict()

  defp source_terms_match(quote, rfq, row) do
    with {:ok, quantity} <- cast_decimal(row["quoted_quantity"]),
         {:ok, unit_price} <- cast_decimal(row["unit_price"]),
         {:ok, total_price} <- cast_decimal(row["total_price"]),
         true <- row["supplier_party_id"] == quote.supplier_party_id,
         true <- Decimal.equal?(quantity, quote.quoted_quantity),
         true <- Decimal.equal?(unit_price, quote.unit_price),
         true <- Decimal.equal?(total_price, Decimal.mult(quantity, unit_price)),
         true <- row["currency_code"] == quote.currency_code,
         true <- quote.currency_code == rfq.settlement_currency_code,
         true <- row["delivery_days"] == quote.delivery_days,
         true <- is_map(quote.evidence_metadata) do
      :ok
    else
      _mismatch -> integrity_conflict()
    end
  end

  defp cast_decimal(value) do
    case Decimal.cast(value) do
      {:ok, decimal} -> {:ok, Decimal.normalize(decimal)}
      :error -> :error
    end
  end

  defp source_view(comparison, rfq, requisition, quote, row) do
    %{
      "formula_version" => 1,
      "quote_comparison_id" => comparison.id,
      "quote_comparison_version" => comparison.lock_version,
      "rfq_id" => rfq.id,
      "rfq_version" => rfq.lock_version,
      "requisition_id" => requisition.id,
      "requisition_version" => requisition.lock_version,
      "sourcing_lane_id" => requisition.sourcing_lane_id,
      "sourcing_lane_version" => requisition.sourcing_lane_version,
      "selected_quote_id" => quote.id,
      "selected_quote_version" => quote.lock_version,
      "supplier_party_id" => quote.supplier_party_id,
      "quantity" => Decimal.to_string(quote.quoted_quantity, :normal),
      "unit_code" => requisition.unit_code,
      "unit_price" => Decimal.to_string(quote.unit_price, :normal),
      "total_price" => row["total_price"],
      "currency_code" => quote.currency_code,
      "delivery_days" => quote.delivery_days,
      "required_by" => Date.to_iso8601(requisition.required_by),
      "quote_evidence" => bounded_evidence(quote.evidence_metadata)
    }
  end

  defp bounded_evidence(metadata) do
    Map.take(metadata, ["evidence_id", "sha256", "classification"])
  end

  # Comparison creation captures the comparison-pending RFQ version. The exact
  # approval transaction advances that RFQ once into the compared state.
  defp require_decided_rfq_version(rfq, comparison),
    do: Support.require_version(rfq, comparison.rfq_version + 1)

  defp require_status(%{status: status}, status, _message), do: :ok
  defp require_status(_record, _status, message), do: Support.conflict(message)

  defp integrity_conflict,
    do: Support.conflict("approved comparison source failed integrity checks")
end
