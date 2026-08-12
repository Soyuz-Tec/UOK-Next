defmodule UokNext.Modules.Platform.Integrations.Public do
  @moduledoc """
  Supported boundary for provider-neutral connector receipt operations.
  """

  alias UokNext.Modules.Platform.Integrations.Application.ConnectorReceipts
  alias UokNext.Modules.Platform.Integrations.Infrastructure.EctoConnectorReceiptStore

  @spec begin_attempt(map(), UokNext.Kernel.CommandContext.t(), String.t()) :: tuple()
  def begin_attempt(attrs, context, idempotency_key) do
    ConnectorReceipts.begin_attempt(EctoConnectorReceiptStore, attrs, context, idempotency_key)
  end

  @spec reconcile(String.t(), integer(), map(), UokNext.Kernel.CommandContext.t(), String.t()) ::
          tuple()
  def reconcile(receipt_id, expected_version, attrs, context, idempotency_key) do
    ConnectorReceipts.reconcile(
      EctoConnectorReceiptStore,
      receipt_id,
      expected_version,
      attrs,
      context,
      idempotency_key
    )
  end

  @spec get(String.t(), UokNext.Kernel.CommandContext.t()) :: tuple()
  def get(receipt_id, context),
    do: ConnectorReceipts.get(EctoConnectorReceiptStore, receipt_id, context)
end
