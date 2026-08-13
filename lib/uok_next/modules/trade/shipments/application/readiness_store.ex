defmodule UokNext.Modules.Trade.Shipments.Application.ReadinessStore do
  @moduledoc "Persistence port for shipment-readiness cases."

  @callback create(map(), term()) :: tuple()
  @callback fetch(Ecto.UUID.t(), Ecto.UUID.t(), term(), keyword()) :: tuple()
  @callback list(Ecto.UUID.t(), pos_integer(), term()) :: list()
  @callback update(term(), map(), term()) :: tuple()
end
