defmodule UokNext.Modules.Platform.Evidence.Domain.EvidenceObject do
  @moduledoc """
  Immutable, provider-neutral identity for one bounded evidence candidate.

  Object keys are derived exclusively from validated tenant/evidence identities
  and the computed content digest. Callers never supply a storage path.
  """

  @allowed_content_types ~w(
    application/octet-stream
    application/pdf
    image/jpeg
    image/png
    text/plain
  )
  @uuid_pattern ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  @enforce_keys [:id, :tenant_id, :sha256, :byte_size, :content_type, :object_key, :state]
  defstruct [:id, :tenant_id, :sha256, :byte_size, :content_type, :object_key, :state]

  @type t :: %__MODULE__{
          id: String.t(),
          tenant_id: String.t(),
          sha256: String.t(),
          byte_size: pos_integer(),
          content_type: String.t(),
          object_key: String.t(),
          state: String.t()
        }

  @spec new(map(), binary(), pos_integer()) :: {:ok, t()} | {:error, atom()}
  def new(attrs, content, maximum_bytes) when is_map(attrs) and is_binary(content) do
    with {:ok, tenant_id} <- uuid(value(attrs, :tenant_id)),
         {:ok, evidence_id} <- uuid(value(attrs, :id)),
         {:ok, content_type} <- content_type(value(attrs, :content_type)),
         :ok <- content_size(content, maximum_bytes) do
      build(tenant_id, evidence_id, content_type, content)
    end
  end

  def new(_attrs, _content, _maximum_bytes), do: {:error, :invalid_evidence_object}

  @spec verify_content(t(), binary()) :: :ok | {:error, atom()}
  def verify_content(%__MODULE__{} = evidence, content) when is_binary(content) do
    digest = sha256(content)

    if byte_size(content) == evidence.byte_size and digest == evidence.sha256 do
      :ok
    else
      {:error, :integrity_mismatch}
    end
  end

  def verify_content(_evidence, _content), do: {:error, :integrity_mismatch}

  defp build(tenant_id, evidence_id, content_type, content) do
    digest = sha256(content)

    {:ok,
     %__MODULE__{
       id: evidence_id,
       tenant_id: tenant_id,
       sha256: digest,
       byte_size: byte_size(content),
       content_type: content_type,
       object_key: "tenants/#{tenant_id}/evidence/#{evidence_id}/sha256/#{digest}",
       state: "quarantined"
     }}
  end

  defp uuid(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    if Regex.match?(@uuid_pattern, normalized),
      do: {:ok, normalized},
      else: {:error, :invalid_uuid}
  end

  defp uuid(_value), do: {:error, :invalid_uuid}

  defp content_type(value) when value in @allowed_content_types, do: {:ok, value}
  defp content_type(_value), do: {:error, :unsupported_content_type}

  defp content_size(content, maximum_bytes)
       when is_integer(maximum_bytes) and maximum_bytes in 1..8_388_608 do
    if byte_size(content) in 1..maximum_bytes, do: :ok, else: {:error, :invalid_content_size}
  end

  defp content_size(_content, _maximum_bytes), do: {:error, :invalid_content_size}
  defp sha256(content), do: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
end
