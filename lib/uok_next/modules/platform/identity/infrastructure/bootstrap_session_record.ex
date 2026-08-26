defmodule UokNext.Modules.Platform.Identity.Infrastructure.BootstrapSessionRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}

  schema "platform_identity_bootstrap_sessions" do
    field :tenant_id, :binary_id
    field :actor_id, :binary_id
    field :token_hash, :binary
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [:id, :tenant_id, :actor_id, :token_hash, :expires_at])
    |> validate_required([:id, :tenant_id, :actor_id, :token_hash, :expires_at])
    |> unique_constraint([:tenant_id, :token_hash],
      name: :platform_identity_bootstrap_sessions_tenant_token_index
    )
    |> check_constraint(:token_hash,
      name: :platform_identity_bootstrap_sessions_token_hash_check
    )
  end
end
