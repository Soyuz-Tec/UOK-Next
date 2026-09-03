defmodule UokNext.Kernel.OutboxPublisher do
  @moduledoc false

  alias UokNext.Kernel.{DurableJob, OutboxEvent}

  @type delivery :: %{id: Ecto.UUID.t(), consumer: String.t(), event_digest: binary()}
  @type failure_class :: :retryable | :permanent

  @callback deliver(OutboxEvent.t(), DurableJob.t(), keyword()) ::
              {:ok, delivery()} | {:error, String.t(), failure_class()}
end
