defmodule UokNext.Modules.Platform.Evidence.Application.OperationalLineageStore do
  @moduledoc "Persistence port for bounded audit and outbox lineage queries."

  @callback fetch([map()], Ecto.UUID.t(), pos_integer(), term()) :: map()
end
