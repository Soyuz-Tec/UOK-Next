defmodule UokNext.Modules.Platform.Agents.Application.AgentPlanStore do
  @moduledoc """
  Persistence port owned by the agents application layer.
  """

  @type persisted_record :: term()

  @callback new_id() :: String.t()
  @callback create(map(), UokNext.Kernel.CommandContext.t()) ::
              {:ok, persisted_record()} | {:error, map()}
  @callback fetch(String.t(), String.t(), UokNext.Kernel.CommandContext.t()) ::
              {:ok, persisted_record()} | :not_found
  @callback fetch_for_update(String.t(), String.t(), UokNext.Kernel.CommandContext.t()) ::
              {:ok, persisted_record()} | :not_found
  @callback decide(persisted_record(), map(), UokNext.Kernel.CommandContext.t()) ::
              {:ok, persisted_record()} | {:error, :stale | map()}
end
