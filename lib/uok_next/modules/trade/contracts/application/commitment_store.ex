defmodule UokNext.Modules.Trade.Contracts.Application.CommitmentStore do
  @moduledoc "Persistence port for purchase-commitment proposals."

  @callback create(map(), term()) :: tuple()
  @callback fetch(Ecto.UUID.t(), Ecto.UUID.t(), term(), keyword()) :: tuple()
  @callback list(Ecto.UUID.t(), pos_integer(), term()) :: list()
  @callback update(term(), map(), term()) :: tuple()
end
