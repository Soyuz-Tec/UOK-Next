defmodule UokNext.Kernel.OutboxDelivery do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "kernel_outbox_deliveries" do
    field :tenant_id, :binary_id
    field :outbox_event_id, :binary_id
    field :consumer, :string
    field :event_digest, :binary
    field :delivered_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
