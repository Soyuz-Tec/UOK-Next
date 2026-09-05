defmodule UokNext.Modules.Platform.Integrations.Application.ConnectorReceiptStore do
  @moduledoc """
  Persistence port owned by the integrations application layer.
  """

  @type persisted_record :: term()

  @callback transaction_open?() :: boolean()
  @callback create(map(), UokNext.Kernel.CommandContext.t()) ::
              {:ok, persisted_record()} | {:error, map()}
  @callback fetch(String.t(), String.t(), UokNext.Kernel.CommandContext.t()) ::
              {:ok, persisted_record()} | :not_found
  @callback fetch_for_update(String.t(), String.t(), UokNext.Kernel.CommandContext.t()) ::
              {:ok, persisted_record()} | :not_found
  @callback reconcile(persisted_record(), map(), UokNext.Kernel.CommandContext.t()) ::
              {:ok, persisted_record()} | {:error, :stale | map()}
end
