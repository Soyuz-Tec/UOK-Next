defmodule UokNext.Release.ObjectStoreQualification do
  @moduledoc false

  alias UokNext.Modules.Platform.Evidence.Application.EvidenceObjects
  alias UokNext.Modules.Platform.Evidence.Infrastructure.S3ObjectStore

  @spec run!() :: :ok
  def run! do
    content = :crypto.strong_rand_bytes(256)

    attrs = %{
      tenant_id: Ecto.UUID.generate(),
      id: Ecto.UUID.generate(),
      content_type: "application/octet-stream"
    }

    with :ok <- EvidenceObjects.ready?(),
         {:ok, stored} <- EvidenceObjects.store_candidate(attrs, content),
         {:error, _collision_reason} <- EvidenceObjects.store_candidate(attrs, content),
         :ok <- EvidenceObjects.delete_candidate(stored.evidence),
         {:error, :not_found} <- S3ObjectStore.fetch(stored.evidence) do
      IO.puts("Object-store create-only, integrity, and deletion qualification passed.")
      :ok
    else
      _error -> raise "object-store qualification failed"
    end
  end
end
