defmodule UokNext.Kernel.DurableJob do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "kernel_durable_jobs" do
    field :tenant_id, :binary_id
    field :job_kind, :string
    field :outbox_event_id, :binary_id
    field :status, :string
    field :run_at, :utc_datetime_usec
    field :attempt_count, :integer
    field :max_attempts, :integer
    field :lease_token, :binary_id
    field :lease_expires_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :last_error_code, :string
    timestamps(type: :utc_datetime_usec)
  end
end
