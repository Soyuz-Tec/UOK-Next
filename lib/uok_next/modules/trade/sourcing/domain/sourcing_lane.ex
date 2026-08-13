defmodule UokNext.Modules.Trade.Sourcing.Domain.SourcingLane do
  @moduledoc "Pure validation and lifecycle rules for a sourcing lane."

  @classifications ~w(public internal confidential restricted)
  @stable_identifier_pattern ~r/^[A-Za-z0-9][A-Za-z0-9._:\/-]{2,99}$/
  @uuid_pattern ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
  @sha256_pattern ~r/^[0-9a-f]{64}$/i

  @spec validate_create(map()) :: {:ok, map()} | {:error, map()}
  def validate_create(attrs) when is_map(attrs) do
    with {:ok, stable_identifier} <- stable_identifier(value(attrs, :stable_identifier)),
         {:ok, name} <- bounded_text(value(attrs, :name), :name, 2, 200),
         {:ok, supplier_party_id} <- uuid(value(attrs, :supplier_party_id), :supplier_party_id),
         {:ok, product_id} <- uuid(value(attrs, :product_id), :product_id),
         {:ok, origin_location_id} <-
           uuid(value(attrs, :origin_location_id), :origin_location_id),
         {:ok, destination_location_id} <-
           uuid(value(attrs, :destination_location_id), :destination_location_id),
         :ok <- distinct_locations(origin_location_id, destination_location_id),
         {:ok, reason} <- bounded_text(value(attrs, :reason), :reason, 3, 500) do
      {:ok,
       %{
         stable_identifier: stable_identifier,
         name: name,
         supplier_party_id: supplier_party_id,
         product_id: product_id,
         origin_location_id: origin_location_id,
         destination_location_id: destination_location_id,
         reason: reason
       }}
    end
  end

  def validate_create(_attrs), do: error(:command, "must be an object")

  @spec validate_evidence(String.t(), map()) :: {:ok, map()} | {:error, map()}
  def validate_evidence(status, attrs) when is_map(attrs) do
    with :ok <- validate_evidence_state(status),
         {:ok, evidence_id} <- uuid(value(attrs, :evidence_id), :evidence_id),
         {:ok, sha256} <- sha256(value(attrs, :sha256)),
         {:ok, classification} <-
           member(value(attrs, :classification), :classification, @classifications),
         {:ok, reason} <- bounded_text(value(attrs, :reason), :reason, 3, 500) do
      {:ok,
       %{
         evidence: %{
           "evidence_id" => evidence_id,
           "sha256" => sha256,
           "classification" => classification
         },
         reason: reason
       }}
    end
  end

  def validate_evidence(_status, _attrs), do: error(:status, "does not allow evidence submission")

  @spec validate_evidence_state(String.t()) :: :ok | {:error, map()}
  def validate_evidence_state(status) when status in ["draft", "hold"], do: :ok
  def validate_evidence_state(_status), do: error(:status, "does not allow evidence submission")

  @spec validate_decision(String.t(), map() | nil, map()) :: {:ok, map()} | {:error, map()}
  def validate_decision(status, evidence, attrs) when is_map(attrs) do
    with {:ok, decision} <- member(value(attrs, :decision), :decision, ~w(approve hold)),
         {:ok, reason} <- bounded_text(value(attrs, :reason), :reason, 3, 500),
         :ok <- decision_allowed(status, evidence, decision) do
      {:ok, %{decision: decision, reason: reason}}
    end
  end

  def validate_decision(_status, _evidence, _attrs), do: error(:command, "must be an object")

  defp decision_allowed("evidence_submitted", evidence, "approve") when is_map(evidence), do: :ok
  defp decision_allowed("evidence_submitted", _evidence, "hold"), do: :ok
  defp decision_allowed(_status, _evidence, "approve"), do: error(:evidence, "is required")

  defp decision_allowed(_status, _evidence, _decision),
    do: error(:status, "does not allow decision")

  defp distinct_locations(id, id), do: error(:destination_location_id, "must differ from origin")
  defp distinct_locations(_origin, _destination), do: :ok

  defp stable_identifier(value) when is_binary(value) do
    normalized = String.trim(value)

    if Regex.match?(@stable_identifier_pattern, normalized),
      do: {:ok, normalized},
      else: error(:stable_identifier, "must contain 3 to 100 safe characters")
  end

  defp stable_identifier(_value),
    do: error(:stable_identifier, "must contain 3 to 100 safe characters")

  defp sha256(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    if Regex.match?(@sha256_pattern, normalized),
      do: {:ok, normalized},
      else: error(:sha256, "must be a hexadecimal SHA-256 digest")
  end

  defp sha256(_value), do: error(:sha256, "must be a hexadecimal SHA-256 digest")

  defp uuid(value, field) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    if Regex.match?(@uuid_pattern, normalized),
      do: {:ok, normalized},
      else: error(field, "must be a UUID")
  end

  defp uuid(_value, field), do: error(field, "must be a UUID")

  defp bounded_text(value, field, minimum, maximum) when is_binary(value) do
    normalized = String.trim(value)
    length = String.length(normalized)

    if String.printable?(normalized) and length in minimum..maximum,
      do: {:ok, normalized},
      else: error(field, "must contain #{minimum} to #{maximum} printable characters")
  end

  defp bounded_text(_value, field, minimum, maximum),
    do: error(field, "must contain #{minimum} to #{maximum} printable characters")

  defp member(value, field, allowed) do
    if value in allowed, do: {:ok, value}, else: error(field, "is not allowed")
  end

  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  defp error(field, message), do: {:error, %{field => [message]}}
end
