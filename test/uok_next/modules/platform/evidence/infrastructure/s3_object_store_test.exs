defmodule UokNext.Modules.Platform.Evidence.Infrastructure.S3ObjectStoreTest do
  use ExUnit.Case, async: false

  @moduletag :object_store_integration

  alias UokNext.Modules.Platform.Evidence.Application.EvidenceObjects
  alias UokNext.Modules.Platform.Evidence.Infrastructure.S3ObjectStore

  setup do
    previous = Application.get_env(:uok_next, :object_store)

    Application.put_env(:uok_next, :object_store,
      adapter: S3ObjectStore,
      scheme: "http://",
      host: System.get_env("UOK_OBJECT_STORE_TEST_HOST", "127.0.0.1"),
      port: String.to_integer(System.get_env("UOK_OBJECT_STORE_TEST_PORT", "18333")),
      access_key_id: System.fetch_env!("UOK_OBJECT_STORE_ACCESS_KEY"),
      secret_access_key: System.fetch_env!("UOK_OBJECT_STORE_SECRET_KEY"),
      bucket: System.get_env("UOK_OBJECT_STORE_BUCKET", "uok-evidence"),
      region: "us-east-1",
      max_object_bytes: 8_388_608
    )

    on_exit(fn ->
      if previous do
        Application.put_env(:uok_next, :object_store, previous)
      else
        Application.delete_env(:uok_next, :object_store)
      end
    end)
  end

  test "round-trips and removes a content-addressed candidate through S3" do
    attrs = %{
      tenant_id: Ecto.UUID.generate(),
      id: Ecto.UUID.generate(),
      content_type: "application/octet-stream"
    }

    assert :ok = EvidenceObjects.ready?()
    assert {:ok, stored} = EvidenceObjects.store_candidate(attrs, "s3 integration proof")

    assert {:error, _collision_reason} =
             EvidenceObjects.store_candidate(attrs, "s3 integration proof")

    assert stored.receipt.provider == "s3"
    assert stored.receipt.bucket == "uok-evidence"
    assert :ok = EvidenceObjects.delete_candidate(stored.evidence)
    assert {:error, :not_found} = S3ObjectStore.fetch(stored.evidence)
  end
end
