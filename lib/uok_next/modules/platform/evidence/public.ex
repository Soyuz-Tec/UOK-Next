defmodule UokNext.Modules.Platform.Evidence.Public do
  @moduledoc """
  Supported command and query boundary for governed evidence objects.
  """

  alias UokNext.Kernel.IdempotencyKey
  alias UokNext.Modules.Platform.Evidence.Application.{EvidenceCandidates, EvidenceObjects}
  alias UokNext.Modules.Platform.Evidence.Domain.EvidenceObject
  alias UokNext.Modules.Platform.Evidence.Infrastructure.EctoEvidenceCandidateStore

  @spec store_party_candidate(String.t(), String.t(), map(), binary(), term(), String.t()) ::
          tuple()
  def store_party_candidate(evidence_id, party_id, attrs, content, context, idempotency_key) do
    with {:ok, stored} <-
           build_and_store(evidence_id, party_id, attrs, content, context, idempotency_key) do
      EvidenceCandidates.verify(
        EctoEvidenceCandidateStore,
        evidence_id,
        bounded_receipt(stored.receipt),
        context,
        IdempotencyKey.derive(idempotency_key, "evidence-verify")
      )
    end
  end

  @spec get_verified_candidate(String.t(), String.t(), term()) :: tuple()
  def get_verified_candidate(evidence_id, party_id, context) do
    EvidenceCandidates.get_verified(
      EctoEvidenceCandidateStore,
      evidence_id,
      "party",
      party_id,
      context
    )
  end

  @spec list_party_evidence(String.t(), term()) :: tuple()
  def list_party_evidence(party_id, context) do
    EvidenceCandidates.list_for_subject(EctoEvidenceCandidateStore, "party", party_id, context)
  end

  defp build_and_store(evidence_id, party_id, attrs, content, context, idempotency_key) do
    object_attrs = %{
      id: evidence_id,
      tenant_id: context.tenant_id,
      content_type: value(attrs, :content_type)
    }

    with {:ok, evidence} <- build_evidence(object_attrs, content) do
      with {:ok, _prepared, _disposition} <-
             EvidenceCandidates.prepare(
               EctoEvidenceCandidateStore,
               prepare_attrs(evidence, party_id, attrs),
               context,
               IdempotencyKey.derive(idempotency_key, "evidence-prepare")
             ) do
        EvidenceObjects.ensure_candidate(object_attrs, content)
      end
    end
  end

  defp build_evidence(attrs, content) do
    maximum =
      Application.fetch_env!(:uok_next, :object_store) |> Keyword.fetch!(:max_object_bytes)

    EvidenceObject.new(attrs, content, maximum)
  end

  defp prepare_attrs(evidence, party_id, attrs) do
    %{
      id: evidence.id,
      subject_type: "party",
      subject_id: party_id,
      classification: value(attrs, :classification),
      content_type: evidence.content_type,
      byte_size: evidence.byte_size,
      sha256: evidence.sha256,
      object_key: evidence.object_key,
      reason: value(attrs, :reason)
    }
  end

  defp bounded_receipt(receipt) do
    digest =
      receipt
      |> Enum.map(fn {key, value} -> {to_string(key), to_string(value || "")} end)
      |> Enum.sort()
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    %{"adapter_role" => "evidence_object_store", "receipt_sha256" => digest}
  end

  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
end
