defmodule UokNext.Modules.Master.Parties.Public do
  @moduledoc """
  Supported command and query boundary for the `master.parties` module.
  """

  alias UokNext.Modules.Master.Parties.Application.Onboarding
  alias UokNext.Modules.Master.Parties.Infrastructure.EctoPartyStore

  @spec create_draft(map(), UokNext.Kernel.CommandContext.t(), String.t()) :: tuple()
  def create_draft(attrs, context, idempotency_key) do
    Onboarding.create_draft(EctoPartyStore, attrs, context, idempotency_key)
  end

  @spec submit_evidence(
          String.t(),
          map(),
          integer(),
          UokNext.Kernel.CommandContext.t(),
          String.t()
        ) ::
          tuple()
  def submit_evidence(party_id, attrs, expected_version, context, idempotency_key) do
    Onboarding.submit_evidence(
      EctoPartyStore,
      party_id,
      attrs,
      expected_version,
      context,
      idempotency_key
    )
  end

  @spec preflight_evidence(String.t(), integer(), UokNext.Kernel.CommandContext.t()) :: tuple()
  def preflight_evidence(party_id, expected_version, context) do
    Onboarding.preflight_evidence(EctoPartyStore, party_id, expected_version, context)
  end

  @spec decide(String.t(), map(), integer(), UokNext.Kernel.CommandContext.t(), String.t()) ::
          tuple()
  def decide(party_id, attrs, expected_version, context, idempotency_key) do
    Onboarding.decide(EctoPartyStore, party_id, attrs, expected_version, context, idempotency_key)
  end

  @spec get(String.t(), UokNext.Kernel.CommandContext.t()) :: tuple()
  def get(party_id, context), do: Onboarding.get(EctoPartyStore, party_id, context)

  @spec require_approved(String.t(), UokNext.Kernel.CommandContext.t()) :: tuple()
  def require_approved(party_id, context),
    do: Onboarding.require_approved(EctoPartyStore, party_id, context)

  @spec list(pos_integer(), UokNext.Kernel.CommandContext.t()) :: tuple()
  def list(limit, context), do: Onboarding.list(EctoPartyStore, limit, context)
end
