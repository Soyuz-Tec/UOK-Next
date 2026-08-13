defmodule UokNext.Modules.Trade.Sourcing.Domain.ProcurementRules do
  @moduledoc "Pure input and lifecycle rules for governed procurement rounds."

  @identifier_pattern ~r|^[A-Za-z0-9][A-Za-z0-9._:/-]{2,99}$|
  @unit_pattern ~r/^[A-Z][A-Z0-9._-]{0,15}$/
  @currency_pattern ~r/^[A-Z]{3}$/
  @uuid_pattern ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

  def validate_requisition(attrs) when is_map(attrs) do
    with {:ok, identifier} <- identifier(value(attrs, :stable_identifier)),
         {:ok, lane_id} <- uuid(value(attrs, :sourcing_lane_id), :sourcing_lane_id),
         {:ok, quantity} <- positive_decimal(value(attrs, :quantity), :quantity),
         {:ok, unit_code} <- code(value(attrs, :unit_code), :unit_code, @unit_pattern),
         {:ok, required_by} <- future_date(value(attrs, :required_by)),
         {:ok, reason} <- text(value(attrs, :reason), :reason, 3, 500) do
      {:ok,
       %{
         stable_identifier: identifier,
         sourcing_lane_id: lane_id,
         quantity: quantity,
         unit_code: unit_code,
         required_by: required_by,
         reason: reason
       }}
    end
  end

  def validate_requisition(_attrs), do: error(:command, "must be an object")

  def validate_rfq(attrs, now \\ DateTime.utc_now())

  def validate_rfq(attrs, now) when is_map(attrs) do
    with {:ok, identifier} <- identifier(value(attrs, :stable_identifier)),
         {:ok, requisition_id} <- uuid(value(attrs, :requisition_id), :requisition_id),
         {:ok, currency} <-
           code(
             value(attrs, :settlement_currency_code),
             :settlement_currency_code,
             @currency_pattern
           ),
         {:ok, deadline} <- future_datetime(value(attrs, :response_deadline), now),
         {:ok, suppliers} <- supplier_ids(value(attrs, :supplier_party_ids)),
         {:ok, reason} <- text(value(attrs, :reason), :reason, 3, 500) do
      {:ok,
       %{
         stable_identifier: identifier,
         requisition_id: requisition_id,
         settlement_currency_code: currency,
         response_deadline: deadline,
         supplier_party_ids: suppliers,
         reason: reason
       }}
    end
  end

  def validate_rfq(_attrs, _now), do: error(:command, "must be an object")

  def validate_quote(attrs) when is_map(attrs) do
    with {:ok, identifier} <- identifier(value(attrs, :stable_identifier)),
         {:ok, rfq_id} <- uuid(value(attrs, :rfq_id), :rfq_id),
         {:ok, supplier_id} <- uuid(value(attrs, :supplier_party_id), :supplier_party_id),
         {:ok, quantity} <- positive_decimal(value(attrs, :quoted_quantity), :quoted_quantity),
         {:ok, price} <- positive_decimal(value(attrs, :unit_price), :unit_price),
         {:ok, currency} <- code(value(attrs, :currency_code), :currency_code, @currency_pattern),
         {:ok, days} <- bounded_integer(value(attrs, :delivery_days), :delivery_days, 0, 3650),
         {:ok, reason} <- text(value(attrs, :reason), :reason, 3, 500) do
      {:ok,
       %{
         stable_identifier: identifier,
         rfq_id: rfq_id,
         supplier_party_id: supplier_id,
         quoted_quantity: quantity,
         unit_price: price,
         currency_code: currency,
         delivery_days: days,
         reason: reason
       }}
    end
  end

  def validate_quote(_attrs), do: error(:command, "must be an object")

  def validate_quote_evidence("draft", attrs) when is_map(attrs) do
    with {:ok, evidence_id} <- uuid(value(attrs, :evidence_id), :evidence_id),
         {:ok, reason} <- text(value(attrs, :reason), :reason, 3, 500) do
      {:ok, %{evidence_id: evidence_id, reason: reason}}
    end
  end

  def validate_quote_evidence(_status, _attrs),
    do: error(:status, "does not allow evidence submission")

  def validate_quote_evidence_state("draft"), do: :ok

  def validate_quote_evidence_state(_status),
    do: error(:status, "does not allow evidence submission")

  def validate_comparison(attrs) when is_map(attrs) do
    with {:ok, identifier} <- identifier(value(attrs, :stable_identifier)),
         {:ok, rfq_id} <- uuid(value(attrs, :rfq_id), :rfq_id),
         {:ok, reason} <- text(value(attrs, :reason), :reason, 3, 500) do
      {:ok, %{stable_identifier: identifier, rfq_id: rfq_id, reason: reason}}
    end
  end

  def validate_comparison(_attrs), do: error(:command, "must be an object")

  def validate_decision("awaiting_review", attrs) when is_map(attrs) do
    with {:ok, decision} <- member(value(attrs, :decision), :decision, ~w(approve hold)),
         {:ok, reason} <- text(value(attrs, :reason), :reason, 3, 500) do
      {:ok, %{decision: decision, reason: reason}}
    end
  end

  def validate_decision(_status, _attrs), do: error(:status, "does not allow decision")

  defp supplier_ids(values) when is_list(values) and length(values) in 2..20 do
    with {:ok, ids} <- collect_uuids(values),
         true <-
           length(Enum.uniq(ids)) == length(ids) || error(:supplier_party_ids, "must be unique") do
      {:ok, ids}
    end
  end

  defp supplier_ids(_values), do: error(:supplier_party_ids, "must contain 2 to 20 suppliers")

  defp collect_uuids(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case uuid(value, :supplier_party_ids) do
        {:ok, id} -> {:cont, {:ok, [id | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp identifier(value) when is_binary(value) do
    normalized = String.trim(value)

    if Regex.match?(@identifier_pattern, normalized),
      do: {:ok, normalized},
      else: error(:stable_identifier, "is invalid")
  end

  defp identifier(_value), do: error(:stable_identifier, "is invalid")

  defp positive_decimal(value, field) do
    case Decimal.cast(value) do
      {:ok, decimal} ->
        normalized = Decimal.normalize(decimal)

        if Decimal.positive?(normalized) and bounded_decimal?(normalized),
          do: {:ok, normalized},
          else: error(field, "must be positive with at most 14 integer and 6 decimal digits")

      :error ->
        error(field, "must be a decimal number")
    end
  end

  defp bounded_decimal?(decimal) do
    decimal
    |> Decimal.to_string(:normal)
    |> then(&Regex.match?(~r/^\d{1,14}(\.\d{1,6})?$/, &1))
  end

  defp future_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        if Date.compare(date, Date.utc_today()) in [:eq, :gt],
          do: {:ok, date},
          else: error(:required_by, "cannot be in the past")

      {:error, _reason} ->
        error(:required_by, "must be an ISO date")
    end
  end

  defp future_date(_value), do: error(:required_by, "must be an ISO date")

  defp future_datetime(value, now) when is_binary(value) do
    with {:ok, datetime, 0} <- DateTime.from_iso8601(value),
         :gt <- DateTime.compare(datetime, now) do
      {:ok, datetime}
    else
      _invalid -> error(:response_deadline, "must be a future UTC ISO datetime")
    end
  end

  defp future_datetime(_value, _now),
    do: error(:response_deadline, "must be a future UTC ISO datetime")

  defp bounded_integer(value, _field, minimum, maximum)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: {:ok, value}

  defp bounded_integer(_value, field, minimum, maximum),
    do: error(field, "must be between #{minimum} and #{maximum}")

  defp code(value, field, pattern) when is_binary(value) do
    normalized = value |> String.trim() |> String.upcase()
    if Regex.match?(pattern, normalized), do: {:ok, normalized}, else: error(field, "is invalid")
  end

  defp code(_value, field, _pattern), do: error(field, "is invalid")

  defp text(value, field, minimum, maximum) when is_binary(value) do
    normalized = String.trim(value)

    if String.printable?(normalized) and String.length(normalized) in minimum..maximum,
      do: {:ok, normalized},
      else: error(field, "must contain #{minimum} to #{maximum} printable characters")
  end

  defp text(_value, field, minimum, maximum),
    do: error(field, "must contain #{minimum} to #{maximum} printable characters")

  defp uuid(value, field) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    if Regex.match?(@uuid_pattern, normalized),
      do: {:ok, normalized},
      else: error(field, "must be a UUID")
  end

  defp uuid(_value, field), do: error(field, "must be a UUID")

  defp member(value, field, allowed),
    do: if(value in allowed, do: {:ok, value}, else: error(field, "is not allowed"))

  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  defp error(field, message), do: {:error, %{field => [message]}}
end
