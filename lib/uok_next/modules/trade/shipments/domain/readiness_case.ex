defmodule UokNext.Modules.Trade.Shipments.Domain.ReadinessCase do
  @moduledoc "Pure validation and lifecycle rules for a shipment-readiness case."

  @identifier_pattern ~r|^[A-Za-z0-9][A-Za-z0-9._:/-]{2,99}$|
  @uuid_pattern ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
  @create_fields ~w(stable_identifier purchase_commitment_proposal_id expected_proposal_version reason)
  @evidence_fields ~w(evidence_id reason)
  @decision_fields ~w(decision reason task_id expected_version)

  def validate_create(attrs) when is_map(attrs) do
    with :ok <- allowed_fields(attrs, @create_fields),
         {:ok, identifier} <- identifier(value(attrs, :stable_identifier)),
         {:ok, proposal_id} <-
           uuid(value(attrs, :purchase_commitment_proposal_id), :purchase_commitment_proposal_id),
         {:ok, reason} <- text(value(attrs, :reason), :reason) do
      {:ok,
       %{
         stable_identifier: identifier,
         purchase_commitment_proposal_id: proposal_id,
         reason: reason
       }}
    end
  end

  def validate_create(_attrs), do: error(:command, "must be an object")

  def validate_evidence(status, attrs) when status in ["draft", "hold"] and is_map(attrs) do
    with :ok <- allowed_fields(attrs, @evidence_fields),
         {:ok, evidence_id} <- uuid(value(attrs, :evidence_id), :evidence_id),
         {:ok, reason} <- text(value(attrs, :reason), :reason) do
      {:ok, %{evidence_id: evidence_id, reason: reason}}
    end
  end

  def validate_evidence(_status, _attrs),
    do: error(:status, "does not allow evidence submission")

  def validate_evidence_state(status) when status in ["draft", "hold"], do: :ok
  def validate_evidence_state(_status), do: error(:status, "does not allow evidence submission")

  def validate_decision("awaiting_review", attrs) when is_map(attrs) do
    with :ok <- allowed_fields(attrs, @decision_fields),
         {:ok, decision} <- member(value(attrs, :decision), ~w(go hold)),
         {:ok, reason} <- text(value(attrs, :reason), :reason) do
      {:ok, %{decision: decision, reason: reason}}
    end
  end

  def validate_decision(_status, _attrs), do: error(:status, "does not allow decision")

  defp identifier(value) when is_binary(value) do
    normalized = String.trim(value)

    if Regex.match?(@identifier_pattern, normalized),
      do: {:ok, normalized},
      else: invalid(:stable_identifier)
  end

  defp identifier(_value), do: invalid(:stable_identifier)

  defp uuid(value, field) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()
    if Regex.match?(@uuid_pattern, normalized), do: {:ok, normalized}, else: invalid_uuid(field)
  end

  defp uuid(_value, field), do: invalid_uuid(field)

  defp text(value, field) when is_binary(value) do
    normalized = String.trim(value)

    if String.printable?(normalized) and String.length(normalized) in 3..500,
      do: {:ok, normalized},
      else: error(field, "must contain 3 to 500 printable characters")
  end

  defp text(_value, field), do: error(field, "must contain 3 to 500 printable characters")

  defp member(value, allowed),
    do: if(value in allowed, do: {:ok, value}, else: error(:decision, "is not allowed"))

  defp allowed_fields(attrs, allowed) do
    unknown = attrs |> Map.keys() |> Enum.map(&to_string/1) |> Enum.reject(&(&1 in allowed))
    if unknown == [], do: :ok, else: error(:command, "contains server-owned or unknown fields")
  end

  defp invalid(field), do: error(field, "is invalid")
  defp invalid_uuid(field), do: error(field, "must be a UUID")
  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  defp error(field, message), do: {:error, %{field => [message]}}
end
