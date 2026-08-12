defmodule UokNext.Modules.Trade.Sourcing.Application.SourcingLaneStore do
  @moduledoc "Persistence port owned by `trade.sourcing`."

  @type persisted_record :: term()

  @callback create(map(), UokNext.Kernel.CommandContext.t()) ::
              {:ok, persisted_record()} | {:error, map()}
  @callback fetch(Ecto.UUID.t(), Ecto.UUID.t(), UokNext.Kernel.CommandContext.t()) ::
              {:ok, persisted_record()} | :not_found
  @callback fetch_for_update(Ecto.UUID.t(), Ecto.UUID.t(), UokNext.Kernel.CommandContext.t()) ::
              {:ok, persisted_record()} | :not_found
  @callback list(Ecto.UUID.t(), pos_integer(), UokNext.Kernel.CommandContext.t()) ::
              [persisted_record()]
  @callback update(persisted_record(), map(), UokNext.Kernel.CommandContext.t()) ::
              {:ok, persisted_record()} | {:error, :stale | map()}
end
