defmodule UokNext.Modules.Platform.Integrations.Domain.ConnectorReceipt do
  @moduledoc """
  Pure validation and lifecycle rules for outbound connector receipts.
  """

  @identifier_pattern ~r/^[a-z][a-z0-9_.:-]{2,119}$/
  @subject_pattern ~r/^[a-z][a-z0-9_.:-]{1,119}$/
  @delivery_pattern ~r/^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$/
  @digest_pattern ~r/^[0-9a-f]{64}$/
  @uuid_pattern ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
  @outcomes ~w(succeeded retryable_failure permanent_failure timed_out)

  @spec validate_attempt(map()) :: {:ok, map()} | {:error, map()}
  def validate_attempt(attrs) when is_map(attrs) do
    with {:ok, connector_role} <- identifier(value(attrs, :connector_role), :connector_role),
         {:ok, operation} <- identifier(value(attrs, :operation), :operation),
         {:ok, delivery_key} <- delivery_key(value(attrs, :delivery_key)),
         {:ok, request_sha256} <- digest(value(attrs, :request_sha256), :request_sha256),
         {:ok, subject_type} <- subject_type(value(attrs, :subject_type)),
         {:ok, subject_id} <- uuid(value(attrs, :subject_id), :subject_id),
         {:ok, subject_version} <- positive(value(attrs, :subject_version), :subject_version),
         {:ok, timeout_ms} <- bounded(value(attrs, :timeout_ms), :timeout_ms, 100, 120_000),
         {:ok, previous_receipt_id} <- optional_uuid(value(attrs, :previous_receipt_id)),
         {:ok, reason} <- reason(value(attrs, :reason)) do
      {:ok,
       %{
         connector_role: connector_role,
         operation: operation,
         delivery_key: delivery_key,
         request_sha256: request_sha256,
         subject_type: subject_type,
         subject_id: subject_id,
         subject_version: subject_version,
         timeout_ms: timeout_ms,
         previous_receipt_id: previous_receipt_id,
         reason: reason
       }}
    end
  end

  def validate_attempt(_attrs), do: error(:command, "must be an object")

  @spec validate_id(term()) :: {:ok, String.t()} | {:error, map()}
  def validate_id(value), do: uuid(value, :receipt_id)

  @spec validate_retry(map(), map()) :: :ok | {:error, map()}
  def validate_retry(previous, command) when is_map(previous) and is_map(command) do
    with :ok <- retryable(previous),
         :ok <- same(previous, command, :connector_role),
         :ok <- same(previous, command, :operation),
         :ok <- same(previous, command, :delivery_key),
         :ok <- same(previous, command, :request_sha256),
         :ok <- same(previous, command, :subject_type),
         :ok <- same(previous, command, :subject_id) do
      same(previous, command, :subject_version)
    end
  end

  @spec validate_outcome(map(), map(), DateTime.t()) :: {:ok, map()} | {:error, map()}
  def validate_outcome(receipt, attrs, now) when is_map(receipt) and is_map(attrs) do
    with :ok <- attempted(receipt),
         :ok <- no_raw_response(attrs),
         {:ok, status} <- member(value(attrs, :status), :status, @outcomes),
         :ok <- deadline(receipt.deadline_at, status, now),
         {:ok, response_sha256} <- optional_digest(value(attrs, :response_sha256)),
         {:ok, external_reference} <- external_reference(value(attrs, :external_reference)),
         {:ok, retry_after_seconds} <- retry_after(value(attrs, :retry_after_seconds)),
         {:ok, reason} <- reason(value(attrs, :reason)),
         :ok <- outcome_shape(status, response_sha256, external_reference, retry_after_seconds) do
      {:ok,
       %{
         status: status,
         response_sha256: response_sha256,
         external_reference: external_reference,
         retry_after_seconds: retry_after_seconds,
         outcome_reason: reason
       }}
    end
  end

  def validate_outcome(_receipt, _attrs, _now), do: error(:command, "must be an object")

  defp retryable(%{status: status}) when status in ~w(retryable_failure timed_out), do: :ok
  defp retryable(_receipt), do: error(:previous_receipt_id, "does not permit a retry")

  defp attempted(%{status: "attempted"}), do: :ok
  defp attempted(_receipt), do: error(:status, "does not permit reconciliation")

  defp same(previous, command, field) do
    if Map.fetch!(previous, field) == Map.fetch!(command, field),
      do: :ok,
      else: error(field, "must match the previous attempt")
  end

  defp deadline(deadline_at, "timed_out", now) do
    if DateTime.compare(now, deadline_at) == :lt,
      do: error(:status, "cannot time out before the server deadline"),
      else: :ok
  end

  defp deadline(deadline_at, _status, now) do
    if DateTime.compare(now, deadline_at) == :lt,
      do: :ok,
      else: error(:status, "must be timed_out after the server deadline")
  end

  defp outcome_shape("succeeded", response, _reference, nil) when is_binary(response), do: :ok

  defp outcome_shape(status, _response, nil, retry_after)
       when status in ~w(retryable_failure timed_out) and is_integer(retry_after),
       do: :ok

  defp outcome_shape("permanent_failure", _response, nil, nil), do: :ok

  defp outcome_shape(_status, _response, _reference, _retry),
    do: error(:outcome, "has invalid evidence or retry classification")

  defp no_raw_response(attrs) do
    forbidden =
      ~w(response response_body raw_response)a ++ ~w(response response_body raw_response)

    if Enum.any?(forbidden, &Map.has_key?(attrs, &1)),
      do: error(:response, "raw connector responses are not accepted"),
      else: :ok
  end

  defp identifier(item, field) when is_binary(item) do
    normalized = String.trim(item)
    if Regex.match?(@identifier_pattern, normalized), do: {:ok, normalized}, else: invalid(field)
  end

  defp identifier(_item, field), do: invalid(field)

  defp subject_type(item) when is_binary(item) do
    normalized = String.trim(item)

    if Regex.match?(@subject_pattern, normalized),
      do: {:ok, normalized},
      else: invalid(:subject_type)
  end

  defp subject_type(_item), do: invalid(:subject_type)

  defp delivery_key(item) when is_binary(item) do
    normalized = String.trim(item)

    if Regex.match?(@delivery_pattern, normalized),
      do: {:ok, normalized},
      else: invalid(:delivery_key)
  end

  defp delivery_key(_item), do: invalid(:delivery_key)

  defp digest(item, field) when is_binary(item) do
    normalized = item |> String.trim() |> String.downcase()

    if Regex.match?(@digest_pattern, normalized),
      do: {:ok, normalized},
      else: invalid_digest(field)
  end

  defp digest(_item, field), do: invalid_digest(field)
  defp optional_digest(nil), do: {:ok, nil}
  defp optional_digest(item), do: digest(item, :response_sha256)

  defp uuid(item, field) when is_binary(item) do
    normalized = item |> String.trim() |> String.downcase()
    if Regex.match?(@uuid_pattern, normalized), do: {:ok, normalized}, else: invalid_uuid(field)
  end

  defp uuid(_item, field), do: invalid_uuid(field)

  defp optional_uuid(nil), do: {:ok, nil}
  defp optional_uuid(item), do: uuid(item, :previous_receipt_id)
  defp positive(item, _field) when is_integer(item) and item > 0, do: {:ok, item}
  defp positive(_item, field), do: error(field, "must be a positive integer")

  defp bounded(item, _field, minimum, maximum)
       when is_integer(item) and item >= minimum and item <= maximum,
       do: {:ok, item}

  defp bounded(_item, field, minimum, maximum),
    do: error(field, "must be between #{minimum} and #{maximum}")

  defp retry_after(nil), do: {:ok, nil}
  defp retry_after(item), do: bounded(item, :retry_after_seconds, 0, 86_400)

  defp external_reference(nil), do: {:ok, nil}

  defp external_reference(item) when is_binary(item) do
    normalized = String.trim(item)

    if String.printable?(normalized) and String.length(normalized) in 1..200,
      do: {:ok, normalized},
      else: error(:external_reference, "must contain 1 to 200 printable characters")
  end

  defp external_reference(_item),
    do: error(:external_reference, "must contain 1 to 200 printable characters")

  defp reason(item) when is_binary(item) do
    normalized = String.trim(item)

    if String.printable?(normalized) and String.length(normalized) in 3..500,
      do: {:ok, normalized},
      else: error(:reason, "must contain 3 to 500 printable characters")
  end

  defp reason(_item), do: error(:reason, "must contain 3 to 500 printable characters")

  defp member(item, field, allowed) do
    if item in allowed, do: {:ok, item}, else: error(field, "is not allowed")
  end

  defp invalid(field), do: error(field, "must contain a governed identifier")
  defp invalid_uuid(field), do: error(field, "must be a UUID")
  defp invalid_digest(field), do: error(field, "must be a lowercase SHA-256 digest")
  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  defp error(field, message), do: {:error, %{field: Atom.to_string(field), message: message}}
end
