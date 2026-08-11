defmodule UokNext.Modules.Platform.Evidence.Application.EvidenceObjectsTest do
  use ExUnit.Case, async: false

  alias UokNext.Modules.Platform.Evidence.Application.EvidenceObjects

  defmodule MemoryObjectStore do
    @behaviour UokNext.Modules.Platform.Evidence.Application.ObjectStore

    @impl true
    def ready?, do: :ok

    @impl true
    def put(evidence, content) do
      Process.put({__MODULE__, evidence.object_key}, content)

      {:ok, %{provider: "memory", bucket: "test-evidence", key: evidence.object_key, etag: nil}}
    end

    @impl true
    def fetch(evidence) do
      case Process.get({__MODULE__, evidence.object_key}) do
        nil -> {:error, :not_found}
        content -> {:ok, content}
      end
    end

    @impl true
    def delete(evidence) do
      Process.delete({__MODULE__, evidence.object_key})
      :ok
    end
  end

  defmodule TamperingObjectStore do
    @behaviour UokNext.Modules.Platform.Evidence.Application.ObjectStore

    @impl true
    def ready?, do: :ok

    @impl true
    def put(evidence, _content) do
      {:ok, %{provider: "tampered", bucket: "test", key: evidence.object_key}}
    end

    @impl true
    def fetch(_evidence), do: {:ok, "different bytes"}

    @impl true
    def delete(_evidence), do: :ok
  end

  setup do
    previous = Application.get_env(:uok_next, :object_store)
    Application.put_env(:uok_next, :object_store, max_object_bytes: 1_024)

    on_exit(fn ->
      if previous do
        Application.put_env(:uok_next, :object_store, previous)
      else
        Application.delete_env(:uok_next, :object_store)
      end
    end)
  end

  test "stores only after a successful read-after-write integrity check" do
    attrs = valid_attrs()
    content = "candidate evidence"

    assert :ok = EvidenceObjects.ready?(MemoryObjectStore)

    assert {:ok, stored} =
             EvidenceObjects.store_candidate(attrs, content, MemoryObjectStore)

    assert stored.evidence.state == "quarantined"
    assert stored.receipt.provider == "memory"
    assert {:ok, ^content} = MemoryObjectStore.fetch(stored.evidence)
    assert :ok = EvidenceObjects.delete_candidate(stored.evidence, MemoryObjectStore)
    assert {:error, :not_found} = MemoryObjectStore.fetch(stored.evidence)
  end

  test "rejects a provider that returns bytes with the wrong digest" do
    assert {:error, :integrity_mismatch} =
             EvidenceObjects.store_candidate(valid_attrs(), "candidate", TamperingObjectStore)
  end

  defp valid_attrs do
    %{
      tenant_id: Ecto.UUID.generate(),
      id: Ecto.UUID.generate(),
      content_type: "application/octet-stream"
    }
  end
end
