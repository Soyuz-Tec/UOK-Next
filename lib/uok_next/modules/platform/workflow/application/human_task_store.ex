defmodule UokNext.Modules.Platform.Workflow.Application.HumanTaskStore do
  @moduledoc """
  Persistence port owned by the workflow application layer.
  """

  @type persisted_record :: term()

  @callback create(map(), UokNext.Kernel.CommandContext.t()) ::
              {:ok, persisted_record()} | {:error, map()}
  @callback fetch_for_update(
              Ecto.UUID.t(),
              Ecto.UUID.t(),
              UokNext.Kernel.CommandContext.t()
            ) :: {:ok, persisted_record()} | :not_found
  @callback complete(persisted_record(), map(), UokNext.Kernel.CommandContext.t()) ::
              {:ok, persisted_record()} | {:error, :stale | map()}
end
