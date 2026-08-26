defmodule UokNext.Modules.Platform.Identity.Infrastructure.LoginThrottleRecord do
  @moduledoc false

  use Ecto.Schema

  @primary_key false

  schema "platform_identity_login_throttles" do
    field :tenant_id, :binary_id, primary_key: true
    field :identifier_hash, :binary, primary_key: true
    field :failed_count, :integer
    field :window_started_at, :utc_datetime_usec
    field :blocked_until, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
