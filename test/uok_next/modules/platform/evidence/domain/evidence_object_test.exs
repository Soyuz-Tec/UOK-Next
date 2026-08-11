defmodule UokNext.Modules.Platform.Evidence.Domain.EvidenceObjectTest do
  use ExUnit.Case, async: true

  alias UokNext.Modules.Platform.Evidence.Domain.EvidenceObject

  test "derives an immutable tenant-scoped key and verifies content integrity" do
    content = "bounded evidence"
    attrs = valid_attrs()

    assert {:ok, evidence} = EvidenceObject.new(attrs, content, 1_024)
    assert evidence.tenant_id == attrs.tenant_id
    assert evidence.id == attrs.id
    assert evidence.byte_size == byte_size(content)
    assert evidence.state == "quarantined"
    assert evidence.object_key =~ "tenants/#{attrs.tenant_id}/evidence/#{attrs.id}/sha256/"
    assert evidence.object_key =~ evidence.sha256
    assert :ok = EvidenceObject.verify_content(evidence, content)
    assert {:error, :integrity_mismatch} = EvidenceObject.verify_content(evidence, "tampered")
  end

  test "rejects invalid identities, content types, empty input, and oversized input" do
    assert {:error, :invalid_uuid} =
             EvidenceObject.new(%{valid_attrs() | tenant_id: "../escape"}, "bytes", 1_024)

    assert {:error, :unsupported_content_type} =
             EvidenceObject.new(%{valid_attrs() | content_type: "text/html"}, "bytes", 1_024)

    assert {:error, :invalid_content_size} = EvidenceObject.new(valid_attrs(), "", 1_024)

    assert {:error, :invalid_content_size} =
             EvidenceObject.new(valid_attrs(), :binary.copy(<<0>>, 1_025), 1_024)

    assert {:error, :invalid_content_size} =
             EvidenceObject.new(valid_attrs(), "bytes", 8_388_609)
  end

  defp valid_attrs do
    %{
      tenant_id: Ecto.UUID.generate(),
      id: Ecto.UUID.generate(),
      content_type: "application/pdf"
    }
  end
end
