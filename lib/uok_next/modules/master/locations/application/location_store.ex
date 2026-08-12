defmodule UokNext.Modules.Master.Locations.Application.LocationStore do
  @moduledoc "Persistence port owned by `master.locations`."

  @type persisted_record :: term()

  @callback create(map(), UokNext.Kernel.CommandContext.t()) ::
              {:ok, persisted_record()} | {:error, map()}
  @callback fetch(Ecto.UUID.t(), Ecto.UUID.t(), UokNext.Kernel.CommandContext.t()) ::
              {:ok, persisted_record()} | :not_found
  @callback list(Ecto.UUID.t(), pos_integer(), UokNext.Kernel.CommandContext.t()) ::
              [persisted_record()]
end
