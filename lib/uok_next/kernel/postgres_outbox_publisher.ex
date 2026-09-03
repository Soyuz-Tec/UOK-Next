defmodule UokNext.Kernel.PostgresOutboxPublisher do
  @moduledoc """
  Delivers one outbox event to the bounded PostgreSQL handoff receipt.

  The receipt is idempotent and stores no event payload. It proves only a
  durable internal handoff, never an external side effect.
  """

  import Ecto.Query

  @behaviour UokNext.Kernel.OutboxPublisher

  alias UokNext.Kernel.{DurableJob, OutboxDelivery, OutboxEvent}

  @consumer "kernel.local_handoff.v1"

  @impl true
  def deliver(%OutboxEvent{} = event, %DurableJob{}, options) do
    repo = Keyword.fetch!(options, :repo)
    now = Keyword.fetch!(options, :now)
    digest = digest(event)

    result =
      repo.transaction(fn ->
        insert_receipt(repo, event, digest, now)
        receipt = fetch_receipt!(repo, event)

        if receipt.event_digest == digest do
          %{id: receipt.id, consumer: receipt.consumer, event_digest: receipt.event_digest}
        else
          repo.rollback(:delivery_conflict)
        end
      end)

    case result do
      {:ok, receipt} -> {:ok, receipt}
      {:error, :delivery_conflict} -> {:error, "delivery_conflict", :permanent}
    end
  end

  @doc false
  @spec consumer() :: String.t()
  def consumer, do: @consumer

  @doc false
  @spec digest(OutboxEvent.t()) :: binary()
  def digest(%OutboxEvent{} = event) do
    %{
      id: event.id,
      tenant_id: event.tenant_id,
      actor_id: event.actor_id,
      correlation_id: event.correlation_id,
      command_receipt_id: event.command_receipt_id,
      event_name: event.event_name,
      event_version: event.event_version,
      aggregate_type: event.aggregate_type,
      aggregate_id: event.aggregate_id,
      aggregate_version: event.aggregate_version,
      classification: event.classification,
      payload: event.payload
    }
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
  end

  defp insert_receipt(repo, event, digest, now) do
    repo.insert_all(
      OutboxDelivery,
      [
        %{
          id: Ecto.UUID.generate(),
          tenant_id: event.tenant_id,
          outbox_event_id: event.id,
          consumer: @consumer,
          event_digest: digest,
          delivered_at: now,
          inserted_at: now
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:tenant_id, :outbox_event_id, :consumer]
    )
  end

  defp fetch_receipt!(repo, event) do
    repo.one!(
      from delivery in OutboxDelivery,
        where:
          delivery.tenant_id == ^event.tenant_id and
            delivery.outbox_event_id == ^event.id and
            delivery.consumer == ^@consumer
    )
  end
end
