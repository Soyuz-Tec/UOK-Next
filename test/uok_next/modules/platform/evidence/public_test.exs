defmodule UokNext.Modules.Platform.Evidence.PublicTest do
  use UokNext.DataCase, async: true

  import UokNext.PartyOnboardingFixtures

  alias UokNext.Kernel.{
    AuditEvent,
    CommandReceipt,
    IdempotencyKey,
    OutboxEvent,
    TenantTransaction
  }

  alias UokNext.Modules.Platform.Evidence.Application.{EvidenceCandidates, EvidenceObjects}
  alias UokNext.Modules.Platform.Evidence.Domain.EvidenceObject

  alias UokNext.Modules.Platform.Evidence.Infrastructure.{
    EctoEvidenceCandidateStore,
    EvidenceCandidateRecord
  }

  alias UokNext.Modules.Platform.Evidence.Public

  test "persists verified metadata and recovers a retry after bytes were already stored" do
    context = context()
    party = create_party(context)
    evidence_id = Ecto.UUID.generate()
    key = Ecto.UUID.generate()
    content = "bounded registration evidence"
    attrs = evidence_attrs()
    object_attrs = %{id: evidence_id, tenant_id: context.tenant_id, content_type: "text/plain"}

    {:ok, evidence} =
      EvidenceObject.new(
        object_attrs,
        content,
        8_388_608
      )

    prepare_attrs = %{
      id: evidence.id,
      subject_type: "party",
      subject_id: party["id"],
      classification: attrs["classification"],
      content_type: evidence.content_type,
      byte_size: evidence.byte_size,
      sha256: evidence.sha256,
      object_key: evidence.object_key,
      reason: attrs["reason"]
    }

    assert {:ok, prepared, :executed} =
             EvidenceCandidates.prepare(
               EctoEvidenceCandidateStore,
               prepare_attrs,
               context,
               IdempotencyKey.derive(key, "evidence-prepare")
             )

    assert prepared["state"] == "pending_upload"
    assert {:ok, _stored} = EvidenceObjects.ensure_candidate(object_attrs, content)

    upload_attrs = %{
      "classification" => attrs["classification"],
      "content_type" => "text/plain",
      "reason" => attrs["reason"]
    }

    assert {:ok, verified, :executed} =
             Public.store_party_candidate(
               evidence_id,
               party["id"],
               upload_attrs,
               content,
               context,
               key
             )

    assert verified["state"] == "verified"
    assert verified["sha256"] == evidence.sha256
    assert tenant_count(EvidenceCandidateRecord, context) == 1
    assert tenant_count(CommandReceipt, context) == 3
    assert tenant_count(AuditEvent, context) == 3
    assert tenant_count(OutboxEvent, context) == 3
  end

  test "fails closed for foreign tenant, subject substitution, and missing permission" do
    owner = context()
    party = create_party(owner)
    evidence_id = Ecto.UUID.generate()

    assert {:ok, _candidate, :executed} =
             Public.store_party_candidate(
               evidence_id,
               party["id"],
               %{
                 "classification" => "confidential",
                 "content_type" => "text/plain",
                 "reason" => "Store governed registration evidence"
               },
               "registration evidence",
               owner,
               Ecto.UUID.generate()
             )

    assert {:error, hidden} = Public.get_verified_candidate(evidence_id, party["id"], context())
    assert hidden.code == "not_found"

    assert {:error, substituted} =
             Public.get_verified_candidate(evidence_id, Ecto.UUID.generate(), owner)

    assert substituted.code == "not_found"

    denied = context(%{tenant_id: owner.tenant_id, permissions: ["parties:read"]})
    assert {:error, forbidden} = Public.get_verified_candidate(evidence_id, party["id"], denied)
    assert forbidden.code == "forbidden"
  end

  defp tenant_count(schema, context) do
    {:ok, count} =
      TenantTransaction.run(context, fn -> {:ok, Repo.aggregate(schema, :count)} end)

    count
  end
end
