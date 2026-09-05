defmodule UokNext.Modules.Platform.Integrations.Application.CommunicationLinkStore do
  @moduledoc "Persistence port for immutable, tenant-bound communication links."

  @callback create(map(), UokNext.Kernel.CommandContext.t()) :: {:ok, map()} | {:error, map()}
  @callback fetch(String.t(), String.t(), UokNext.Kernel.CommandContext.t()) ::
              {:ok, map()} | :not_found
end
