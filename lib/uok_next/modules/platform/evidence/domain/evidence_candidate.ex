defmodule UokNext.Modules.Platform.Evidence.Domain.EvidenceCandidate do
  @moduledoc """
  Pure lifecycle rules for persisted evidence-object metadata.
  """

  @classifications ~w(public internal confidential restricted)
  @subject_pattern ~r/^[a-z][a-z0-9_.:-]{1,119}$/
  @uuid_pattern ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

  @spec validate_prepare(map()) :: {:ok, map()} | {:error, map()}
  def validate_prepare(attrs) when is_map(attrs) do
    with {:ok, id} <- uuid(value(attrs, :id), :id),
         {:ok, subject_type} <- subject_type(value(attrs, :subject_type)),
         {:ok, subject_id} <- uuid(value(attrs, :subject_id), :subject_id),
         {:ok, classification} <- classification(value(attrs, :classification)),
         {:ok, content_type} <- bounded_text(value(attrs, :content_type), :content_type, 120),
         {:ok, byte_size} <- byte_size_value(value(attrs, :byte_size)),
         {:ok, sha256} <- sha256(value(attrs, :sha256)),
         {:ok, object_key} <- bounded_text(value(attrs, :object_key), :object_key, 512),
         {:ok, reason} <- bounded_text(value(attrs, :reason), :reason, 500) do
      {:ok,
       %{
         id: id,
         subject_type: subject_type,
         subject_id: subject_id,
         classification: classification,
         content_type: content_type,
         byte_size: byte_size,
         sha256: sha256,
         object_key: object_key,
         reason: reason
       }}
    end
  end

  def validate_prepare(_attrs), do: error(:command, "must be an object")

  @spec validate_verification(String.t(), map()) :: {:ok, map()} | {:error, map()}
  def validate_verification("pending_upload", receipt) when is_map(receipt) do
    with {:ok, role} <- bounded_text(value(receipt, :adapter_role), :adapter_role, 80),
         true <- role == "evidence_object_store" || error(:adapter_role, "is not allowed"),
         {:ok, digest} <- sha256(value(receipt, :receipt_sha256)) do
      {:ok, %{"adapter_role" => role, "receipt_sha256" => digest}}
    end
  end

  def validate_verification(_state, _receipt), do: error(:state, "does not allow verification")

  defp subject_type(value) when is_binary(value) do
    if Regex.match?(@subject_pattern, value),
      do: {:ok, value},
      else: error(:subject_type, "is invalid")
  end

  defp subject_type(_value), do: error(:subject_type, "is invalid")
  defp classification(value) when value in @classifications, do: {:ok, value}
  defp classification(_value), do: error(:classification, "is not allowed")

  defp byte_size_value(value) when is_integer(value) and value in 1..8_388_608,
    do: {:ok, value}

  defp byte_size_value(_value), do: error(:byte_size, "must be between 1 and 8388608")

  defp sha256(value) when is_binary(value) do
    normalized = String.downcase(value)

    if Regex.match?(~r/^[0-9a-f]{64}$/, normalized),
      do: {:ok, normalized},
      else: error(:sha256, "is invalid")
  end

  defp sha256(_value), do: error(:sha256, "is invalid")

  defp uuid(value, field) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    if Regex.match?(@uuid_pattern, normalized),
      do: {:ok, normalized},
      else: error(field, "must be a UUID")
  end

  defp uuid(_value, field), do: error(field, "must be a UUID")

  defp bounded_text(value, field, maximum) when is_binary(value) do
    normalized = String.trim(value)

    if normalized != "" and String.printable?(normalized) and String.length(normalized) <= maximum,
      do: {:ok, normalized},
      else: error(field, "must contain at most #{maximum} printable characters")
  end

  defp bounded_text(_value, field, maximum),
    do: error(field, "must contain at most #{maximum} printable characters")

  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  defp error(field, message), do: {:error, %{field => [message]}}
end
