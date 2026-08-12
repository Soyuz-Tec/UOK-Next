defmodule UokNext.Modules.Platform.Evidence.Application.EvidenceCandidateStore do
  @moduledoc false

  @callback create(map(), UokNext.Kernel.CommandContext.t()) :: {:ok, struct()} | {:error, term()}
  @callback fetch(String.t(), String.t(), UokNext.Kernel.CommandContext.t()) ::
              {:ok, struct()} | :not_found
  @callback fetch_for_update(String.t(), String.t(), UokNext.Kernel.CommandContext.t()) ::
              {:ok, struct()} | :not_found
  @callback verify(struct(), map(), UokNext.Kernel.CommandContext.t()) ::
              {:ok, struct()} | {:error, term()}
  @callback list_for_subject(
              String.t(),
              String.t(),
              String.t(),
              UokNext.Kernel.CommandContext.t()
            ) ::
              [struct()]
end
