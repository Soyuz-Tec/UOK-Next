defmodule UokNext.Kernel.OutboxEvent do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "kernel_outbox_events" do
    field :tenant_id, :binary_id
    field :actor_id, :binary_id
    field :correlation_id, :binary_id
    field :command_receipt_id, :binary_id
    field :event_name, :string
    field :event_version, :integer
    field :aggregate_type, :string
    field :aggregate_id, :binary_id
    field :aggregate_version, :integer
    field :classification, :string
    field :payload, :map
    field :status, :string
    field :available_at, :utc_datetime_usec
    field :published_at, :utc_datetime_usec
    field :attempt_count, :integer
    timestamps(type: :utc_datetime_usec)
  end
end
