defmodule UokNext.Modules.Platform.Integrations.Public do
  @moduledoc """
  Supported boundary for provider-neutral connector receipt operations.
  """

  alias UokNext.Modules.Platform.Integrations.Application.{
    CommunicationDeliveries,
    Communications,
    ConnectorReceipts
  }

  alias UokNext.Modules.Platform.Integrations.Infrastructure.{
    CommunicationsAdapter,
    EctoCommunicationLinkStore,
    EctoConnectorReceiptStore
  }

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

  @spec link_communication(map(), UokNext.Kernel.CommandContext.t(), String.t()) :: tuple()
  def link_communication(attrs, context, key),
    do: Communications.link(communication_ports(), attrs, context, key)

  @spec get_communication_link(String.t(), UokNext.Kernel.CommandContext.t()) :: tuple()
  def get_communication_link(id, context),
    do: Communications.get(communication_ports(), id, context)

  @spec request_communication_delivery(
          String.t(),
          map(),
          integer(),
          UokNext.Kernel.CommandContext.t(),
          String.t()
        ) :: tuple()
  def request_communication_delivery(id, attrs, version, context, key),
    do: CommunicationDeliveries.request(communication_ports(), id, attrs, version, context, key)

  @spec reconcile_communication_delivery(
          String.t(),
          String.t(),
          integer(),
          UokNext.Kernel.CommandContext.t(),
          String.t()
        ) :: tuple()
  def reconcile_communication_delivery(link_id, receipt_id, version, context, key),
    do:
      CommunicationDeliveries.reconcile(
        communication_ports(),
        link_id,
        receipt_id,
        version,
        context,
        key
      )

  @spec communications_health(UokNext.Kernel.CommandContext.t()) :: tuple()
  def communications_health(context), do: Communications.health(communication_ports(), context)

  defp communication_ports do
    %{
      links: EctoCommunicationLinkStore,
      receipts: EctoConnectorReceiptStore,
      adapter: CommunicationsAdapter
    }
  end
end
