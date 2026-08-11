defmodule UokNext.Modules.Master.Parties.Domain.PartyProfile do
  @moduledoc """
  Pure validation and lifecycle decisions for a party onboarding profile.
  """

  @party_kinds ~w(organization individual)
  @classifications ~w(public internal confidential restricted)
  @stable_identifier_pattern ~r/^[A-Za-z0-9][A-Za-z0-9._:\/-]{2,99}$/
  @uuid_pattern ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
  @sha256_pattern ~r/^[0-9a-f]{64}$/i

  @type validation_error :: %{field: String.t(), message: String.t()}

  @spec validate_create(map()) :: {:ok, map()} | {:error, validation_error()}
  def validate_create(attrs) when is_map(attrs) do
    with {:ok, stable_identifier} <- stable_identifier(value(attrs, "stable_identifier")),
         {:ok, legal_name} <- bounded_text(value(attrs, "legal_name"), "legal_name", 2, 200),
         {:ok, country_code} <- country_code(value(attrs, "country_code")),
         {:ok, party_kind} <- member(value(attrs, "party_kind"), "party_kind", @party_kinds),
         {:ok, reason} <- reason(value(attrs, "reason")) do
      {:ok,
       %{
         stable_identifier: stable_identifier,
         legal_name: legal_name,
         country_code: country_code,
         party_kind: party_kind,
         reason: reason
       }}
    end
  end

  def validate_create(_attrs), do: error("command", "must be an object")

  @spec validate_evidence(String.t(), map()) :: {:ok, map()} | {:error, validation_error()}
  def validate_evidence(status, attrs) when status in ["draft", "hold"] and is_map(attrs) do
    with {:ok, evidence_id} <- uuid(value(attrs, "evidence_id"), "evidence_id"),
         {:ok, sha256} <- sha256(value(attrs, "sha256")),
         {:ok, classification} <-
           member(value(attrs, "classification"), "classification", @classifications),
         {:ok, reason} <- reason(value(attrs, "reason")) do
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

  def validate_evidence(_status, _attrs) do
    error("status", "does not allow evidence submission")
  end

  @spec validate_decision(String.t(), map() | nil, map()) ::
          {:ok, map()} | {:error, validation_error()}
  def validate_decision(status, evidence, attrs) when is_map(attrs) do
    with {:ok, decision} <- member(value(attrs, "decision"), "decision", ~w(approve hold)),
         {:ok, reason} <- reason(value(attrs, "reason")),
         :ok <- decision_allowed(status, evidence, decision) do
      {:ok, %{decision: decision, reason: reason}}
    end
  end

  def validate_decision(_status, _evidence, _attrs), do: error("command", "must be an object")

  defp decision_allowed("evidence_submitted", evidence, "approve") when is_map(evidence), do: :ok

  defp decision_allowed(status, _evidence, "hold") when status in ["draft", "evidence_submitted"],
    do: :ok

  defp decision_allowed(_status, _evidence, "approve") do
    error("evidence", "must be submitted before approval")
  end

  defp decision_allowed(_status, _evidence, _decision) do
    error("status", "does not allow this onboarding decision")
  end

  defp stable_identifier(value) when is_binary(value) do
    normalized = String.trim(value)

    if Regex.match?(@stable_identifier_pattern, normalized) do
      {:ok, normalized}
    else
      error("stable_identifier", "must contain 3 to 100 safe characters")
    end
  end

  defp stable_identifier(_value) do
    error("stable_identifier", "must contain 3 to 100 safe characters")
  end

  defp country_code(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.upcase()

    if String.match?(normalized, ~r/^[A-Z]{2}$/) do
      {:ok, normalized}
    else
      error("country_code", "must be a two-letter code")
    end
  end

  defp country_code(_value), do: error("country_code", "must be a two-letter code")

  defp sha256(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    if Regex.match?(@sha256_pattern, normalized) do
      {:ok, normalized}
    else
      error("sha256", "must be a hexadecimal SHA-256 digest")
    end
  end

  defp sha256(_value), do: error("sha256", "must be a hexadecimal SHA-256 digest")

  defp uuid(value, field) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    if Regex.match?(@uuid_pattern, normalized) do
      {:ok, normalized}
    else
      error(field, "must be a UUID")
    end
  end

  defp uuid(_value, field), do: error(field, "must be a UUID")

  defp reason(value), do: bounded_text(value, "reason", 3, 500)

  defp bounded_text(value, field, minimum, maximum) when is_binary(value) do
    normalized = String.trim(value)
    length = String.length(normalized)

    if String.printable?(normalized) and length in minimum..maximum do
      {:ok, normalized}
    else
      error(field, "must contain #{minimum} to #{maximum} printable characters")
    end
  end

  defp bounded_text(_value, field, minimum, maximum) do
    error(field, "must contain #{minimum} to #{maximum} printable characters")
  end

  defp member(value, field, allowed) do
    if value in allowed, do: {:ok, value}, else: error(field, "is not allowed")
  end

  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, key_atom(key))

  defp key_atom("stable_identifier"), do: :stable_identifier
  defp key_atom("legal_name"), do: :legal_name
  defp key_atom("country_code"), do: :country_code
  defp key_atom("party_kind"), do: :party_kind
  defp key_atom("reason"), do: :reason
  defp key_atom("evidence_id"), do: :evidence_id
  defp key_atom("sha256"), do: :sha256
  defp key_atom("classification"), do: :classification
  defp key_atom("decision"), do: :decision
  defp error(field, message), do: {:error, %{field: field, message: message}}
end
