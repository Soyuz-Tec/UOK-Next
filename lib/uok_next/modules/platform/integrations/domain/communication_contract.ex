defmodule UokNext.Modules.Platform.Integrations.Domain.CommunicationContract do
  @moduledoc "Pure, content-free contracts for governed communication links and local handoff."

  @uuid ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
  @delivery_key ~r/^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$/
  @link_fields ~w(subject_type subject_id subject_version conversation_id reason)
  @envelope_fields ~w(contract_version system_role tenant_id actor_id subject_type subject_id subject_version conversation_id link_id operation delivery_key)
  @uuid_fields ~w(tenant_id actor_id subject_id conversation_id link_id)

  @spec link(term()) :: {:ok, map()} | {:error, map()}
  def link(attrs) do
    with :ok <- exact_keys(attrs, @link_fields),
         :ok <- fixed(attrs["subject_type"], "party", "subject_type"),
         {:ok, subject_id} <- uuid(attrs["subject_id"], "subject_id"),
         :ok <- positive(attrs["subject_version"], "subject_version"),
         {:ok, conversation_id} <- uuid(attrs["conversation_id"], "conversation_id"),
         {:ok, reason} <- reason(attrs["reason"]) do
      {:ok,
       %{
         subject_type: "party",
         subject_id: subject_id,
         subject_version: attrs["subject_version"],
         conversation_id: conversation_id,
         reason: reason
       }}
    end
  end

  @spec delivery(term()) :: {:ok, map()} | {:error, map()}
  def delivery(attrs) do
    with :ok <- delivery_keys(attrs),
         :ok <- delivery_key(attrs["delivery_key"]),
         {:ok, previous_receipt_id} <- optional_receipt(attrs["previous_receipt_id"]),
         {:ok, reason} <- reason(attrs["reason"]) do
      {:ok,
       %{
         delivery_key: attrs["delivery_key"],
         previous_receipt_id: previous_receipt_id,
         reason: reason
       }}
    end
  end

  @doc """
  Builds the canonical envelope from trusted, freshly resolved application fields.

  Contract version 1 hashes sorted string-key pairs with deterministic Erlang external
  term encoding. This local qualification format does not claim wire interoperability.
  """
  @spec envelope(term()) :: {:ok, map()} | {:error, map()}
  def envelope(attrs) do
    with :ok <- exact_keys(attrs, @envelope_fields),
         :ok <- fixed(attrs["contract_version"], 1, "contract_version"),
         :ok <- fixed(attrs["system_role"], "communications_system", "system_role"),
         :ok <- fixed(attrs["subject_type"], "party", "subject_type"),
         :ok <- operation(attrs["operation"]),
         :ok <- positive(attrs["subject_version"], "subject_version"),
         :ok <- delivery_key(attrs["delivery_key"]),
         {:ok, normalized} <- normalize_uuids(attrs) do
      {:ok, Map.put(normalized, "request_sha256", digest(normalized))}
    end
  end

  @doc "Rejects altered or caller-forged envelopes before an adapter is invoked."
  @spec validate_envelope(term()) :: {:ok, map()} | {:error, map()}
  def validate_envelope(attrs) do
    with :ok <- exact_keys(attrs, ["request_sha256" | @envelope_fields]),
         {:ok, canonical} <- envelope(Map.delete(attrs, "request_sha256")),
         :ok <- fixed(attrs, canonical, "envelope") do
      {:ok, canonical}
    end
  end

  @spec uuid(term(), String.t()) :: {:ok, String.t()} | {:error, map()}
  def uuid(value, field) when is_binary(value) and byte_size(value) == 36 do
    if String.valid?(value) and Regex.match?(@uuid, value),
      do: {:ok, String.downcase(value)},
      else: error(field, "must be a UUID")
  end

  def uuid(_value, field), do: error(field, "must be a UUID")

  @spec exact_keys(term(), [String.t()]) :: :ok | {:error, map()}
  def exact_keys(attrs, fields) when is_map(attrs) do
    if map_size(attrs) == length(fields) and Enum.all?(fields, &Map.has_key?(attrs, &1)),
      do: :ok,
      else: error("command", "requires exactly the documented string-key fields")
  end

  def exact_keys(_attrs, _fields), do: error("command", "must be an object")

  defp delivery_keys(attrs) when is_map(attrs) do
    fields =
      if Map.has_key?(attrs, "previous_receipt_id"),
        do: ~w(delivery_key reason previous_receipt_id),
        else: ~w(delivery_key reason)

    exact_keys(attrs, fields)
  end

  defp delivery_keys(_attrs), do: error("command", "must be an object")
  defp optional_receipt(nil), do: {:ok, nil}
  defp optional_receipt(value), do: uuid(value, "previous_receipt_id")

  defp normalize_uuids(attrs) do
    Enum.reduce_while(@uuid_fields, {:ok, attrs}, fn field, {:ok, normalized} ->
      case uuid(attrs[field], field) do
        {:ok, value} -> {:cont, {:ok, Map.put(normalized, field, value)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp digest(envelope) do
    envelope
    |> Enum.sort()
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp reason(value) when is_binary(value) and byte_size(value) <= 2_000 do
    if String.valid?(value) do
      normalized = String.trim(value)

      if String.printable?(normalized) and String.length(normalized) in 3..500,
        do: {:ok, normalized},
        else: error("reason", "must contain 3 to 500 printable characters")
    else
      error("reason", "must contain 3 to 500 printable characters")
    end
  end

  defp reason(_value), do: error("reason", "must contain 3 to 500 printable characters")

  defp delivery_key(value) when is_binary(value) and byte_size(value) in 8..128 do
    if String.valid?(value) and Regex.match?(@delivery_key, value),
      do: :ok,
      else: error("delivery_key", "must be a safe 8 to 128 character identifier")
  end

  defp delivery_key(_value),
    do: error("delivery_key", "must be a safe 8 to 128 character identifier")

  defp positive(value, _field) when is_integer(value) and value > 0, do: :ok
  defp positive(_value, field), do: error(field, "must be a positive integer")
  defp operation(value) when value in ~w(link delivery), do: :ok
  defp operation(_value), do: error("operation", "is not allowed")
  defp fixed(value, value, _field), do: :ok
  defp fixed(_value, _expected, field), do: error(field, "does not match the contract")
  defp error(field, message), do: {:error, %{field: field, message: message}}
end
