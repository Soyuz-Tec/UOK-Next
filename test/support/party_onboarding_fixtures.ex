defmodule UokNext.PartyOnboardingFixtures do
  @moduledoc false

  alias UokNext.Kernel.CommandContext
  alias UokNext.Kernel.TenantTransaction
  alias UokNext.Modules.Master.Parties.Public
  alias UokNext.Modules.Platform.Evidence.Infrastructure.EvidenceCandidateRecord
  alias UokNext.Repo

  def context(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          tenant_id: Ecto.UUID.generate(),
          actor_id: Ecto.UUID.generate(),
          correlation_id: Ecto.UUID.generate(),
          permissions: [
            "parties:create",
            "parties:read",
            "parties:evidence:submit",
            "parties:approve",
            "evidence:read",
            "evidence:upload",
            "workflow:tasks:read"
          ]
        },
        overrides
      )

    {:ok, context} = CommandContext.new(attrs)
    context
  end

  def party_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "stable_identifier" => "party-#{System.unique_integer([:positive])}",
        "legal_name" => "Aseda Trading Limited",
        "country_code" => "gh",
        "party_kind" => "organization",
        "reason" => "Begin governed supplier onboarding"
      },
      overrides
    )
  end

  def evidence_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "evidence_id" => Ecto.UUID.generate(),
        "sha256" => String.duplicate("a", 64),
        "classification" => "confidential",
        "reason" => "Attach verified registration evidence"
      },
      overrides
    )
  end

  def persisted_evidence_attrs(context, party, overrides \\ %{}) do
    attrs = evidence_attrs(overrides)
    now = DateTime.utc_now()

    record_attrs = %{
      id: attrs["evidence_id"],
      tenant_id: context.tenant_id,
      subject_type: "party",
      subject_id: party["id"],
      content_type: "application/pdf",
      byte_size: 128,
      sha256: attrs["sha256"],
      object_key:
        "tenants/#{context.tenant_id}/evidence/#{attrs["evidence_id"]}/sha256/#{attrs["sha256"]}",
      classification: attrs["classification"],
      state: "verified",
      storage_receipt: %{
        "adapter_role" => "evidence_object_store",
        "receipt_sha256" => String.duplicate("b", 64)
      },
      verified_at: now
    }

    {:ok, _record} =
      TenantTransaction.run(context, fn ->
        %EvidenceCandidateRecord{}
        |> EvidenceCandidateRecord.create_changeset(
          Map.drop(record_attrs, [:state, :storage_receipt, :verified_at])
        )
        |> Ecto.Changeset.change(Map.take(record_attrs, [:state, :storage_receipt, :verified_at]))
        |> Repo.insert()
      end)

    attrs
  end

  def create_party(context, overrides \\ %{}) do
    {:ok, party, :executed} =
      Public.create_draft(party_attrs(overrides), context, Ecto.UUID.generate())

    party
  end
end
