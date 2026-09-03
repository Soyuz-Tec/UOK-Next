defmodule UokNext.Modules.Platform.Identity.Infrastructure.PasswordCredentialRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "platform_identity_password_credentials" do
    field :tenant_id, :binary_id
    field :actor_id, :binary_id
    field :password_hash, :string
    field :generation, :integer, default: 1
    field :changed_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [:tenant_id, :actor_id, :password_hash, :generation, :changed_at])
    |> validate_required([:tenant_id, :actor_id, :password_hash, :generation, :changed_at])
    |> unique_constraint([:tenant_id, :actor_id],
      name: :platform_identity_credentials_tenant_actor_index
    )
    |> check_constraint(:generation, name: :platform_identity_credentials_generation_check)
  end

  @spec rotate_changeset(t(), String.t()) :: Ecto.Changeset.t()
  def rotate_changeset(record, password_hash) do
    record
    |> change(
      password_hash: password_hash,
      generation: record.generation + 1,
      changed_at: DateTime.utc_now()
    )
    |> check_constraint(:generation, name: :platform_identity_credentials_generation_check)
  end
end
