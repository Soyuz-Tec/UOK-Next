defmodule UokNext.Kernel.AuditEvent do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "kernel_audit_events" do
    field :tenant_id, :binary_id
    field :actor_id, :binary_id
    field :correlation_id, :binary_id
    field :command_receipt_id, :binary_id
    field :action, :string
    field :resource_type, :string
    field :resource_id, :binary_id
    field :outcome, :string
    field :reason, :string
    field :classification, :string
    field :metadata, :map
    field :occurred_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
