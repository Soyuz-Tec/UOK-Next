defmodule UokNext.Modules.Platform.Evidence.Application.EvidenceObjects do
  @moduledoc """
  Bounded object-store contract used by release qualification.

  It creates only quarantined candidates and verifies a read-after-write digest.
  It is intentionally not exposed as a business or HTTP command in Gate 1.
  """

  alias UokNext.Modules.Platform.Evidence.Domain.EvidenceObject

  @spec ready?(module()) :: :ok | {:error, atom()}
  def ready?(adapter \\ configured_adapter()), do: adapter.ready?()

  @spec store_candidate(map(), binary(), module()) ::
          {:ok, %{evidence: EvidenceObject.t(), receipt: map()}} | {:error, atom()}
  def store_candidate(attrs, content, adapter \\ configured_adapter()) do
    with {:ok, evidence} <- EvidenceObject.new(attrs, content, maximum_bytes()),
         {:ok, receipt} <- adapter.put(evidence, content) do
      verify_stored_candidate(evidence, receipt, adapter)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec delete_candidate(EvidenceObject.t(), module()) :: :ok | {:error, atom()}
  def delete_candidate(evidence, adapter \\ configured_adapter()), do: adapter.delete(evidence)

  defp validate_receipt(%{provider: provider, bucket: bucket, key: key}, evidence)
       when is_binary(provider) and is_binary(bucket) and key == evidence.object_key,
       do: :ok

  defp validate_receipt(_receipt, _evidence), do: {:error, :invalid_storage_receipt}

  defp verify_stored_candidate(evidence, receipt, adapter) do
    with :ok <- validate_receipt(receipt, evidence),
         {:ok, stored_content} <- adapter.fetch(evidence),
         :ok <- EvidenceObject.verify_content(evidence, stored_content) do
      {:ok, %{evidence: evidence, receipt: receipt}}
    else
      {:error, reason} ->
        _cleanup_result = adapter.delete(evidence)
        {:error, reason}
    end
  end

  defp configured_adapter do
    :uok_next
    |> Application.fetch_env!(:object_store)
    |> Keyword.fetch!(:adapter)
  end

  defp maximum_bytes do
    :uok_next
    |> Application.fetch_env!(:object_store)
    |> Keyword.fetch!(:max_object_bytes)
  end
end
