defmodule UokNext.ObjectStoreStub do
  @moduledoc false

  @behaviour UokNext.Modules.Platform.Evidence.Application.ObjectStore

  alias UokNext.Modules.Platform.Evidence.Domain.EvidenceObject

  @impl true
  def ready?, do: :ok

  @impl true
  def put(%EvidenceObject{} = evidence, content) do
    key = process_key(evidence)

    if Process.get(key) do
      {:error, :object_exists}
    else
      Process.put(key, content)
      {:ok, receipt(evidence)}
    end
  end

  @impl true
  def ensure(%EvidenceObject{} = evidence, content) do
    case put(evidence, content) do
      {:ok, receipt} -> {:ok, receipt, :created}
      {:error, :object_exists} -> verify_existing(evidence, content)
    end
  end

  @impl true
  def fetch(%EvidenceObject{} = evidence) do
    case Process.get(process_key(evidence)) do
      content when is_binary(content) -> {:ok, content}
      _missing -> {:error, :not_found}
    end
  end

  @impl true
  def delete(%EvidenceObject{} = evidence) do
    Process.delete(process_key(evidence))
    :ok
  end

  defp verify_existing(evidence, content) do
    with {:ok, stored} <- fetch(evidence),
         true <- stored == content,
         :ok <- EvidenceObject.verify_content(evidence, stored) do
      {:ok, receipt(evidence), :existing}
    else
      _mismatch -> {:error, :object_store_integrity_failure}
    end
  end

  defp receipt(evidence) do
    %{provider: "test", bucket: "test-evidence", key: evidence.object_key, etag: nil}
  end

  defp process_key(evidence), do: {__MODULE__, evidence.object_key}
end
