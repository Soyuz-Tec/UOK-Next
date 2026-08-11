defmodule UokNext.PartyOnboardingFixtures do
  @moduledoc false

  alias UokNext.Kernel.CommandContext
  alias UokNext.Modules.Master.Parties.Public

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
            "parties:approve"
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

  def create_party(context, overrides \\ %{}) do
    {:ok, party, :executed} =
      Public.create_draft(party_attrs(overrides), context, Ecto.UUID.generate())

    party
  end
end
