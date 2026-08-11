defmodule UokNext.Kernel.CommandReceipt do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "kernel_command_receipts" do
    field :tenant_id, :binary_id
    field :actor_id, :binary_id
    field :correlation_id, :binary_id
    field :idempotency_key, :string
    field :command_name, :string
    field :payload_hash, :binary
    field :status, :string
    field :response, :map
    timestamps(type: :utc_datetime_usec)
  end
end
