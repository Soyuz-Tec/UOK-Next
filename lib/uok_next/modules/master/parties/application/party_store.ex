defmodule UokNext.Modules.Master.Parties.Application.PartyStore do
  @moduledoc """
  Persistence port owned by the party-onboarding application layer.
  """

  @type persisted_record :: term()

  @callback create(map(), UokNext.Kernel.CommandContext.t()) ::
              {:ok, persisted_record()} | {:error, map()}
  @callback fetch(Ecto.UUID.t(), Ecto.UUID.t(), UokNext.Kernel.CommandContext.t()) ::
              {:ok, persisted_record()} | :not_found
  @callback fetch_for_update(
              Ecto.UUID.t(),
              Ecto.UUID.t(),
              UokNext.Kernel.CommandContext.t()
            ) ::
              {:ok, persisted_record()} | :not_found
  @callback update(
              persisted_record(),
              :submit_evidence | :decide,
              map(),
              UokNext.Kernel.CommandContext.t()
            ) ::
              {:ok, persisted_record()} | {:error, :stale | map()}
end
