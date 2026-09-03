defmodule UokNext.Modules.Platform.Identity.Infrastructure.UserRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "platform_identity_users" do
    field :tenant_id, :binary_id
    field :username, :string
    field :normalized_username, :string
    field :display_name, :string
    field :access_profile, :string
    field :status, :string, default: "pending_activation"
    field :must_change_password, :boolean, default: true
    field :lock_version, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :tenant_id,
      :username,
      :normalized_username,
      :display_name,
      :access_profile,
      :status,
      :must_change_password
    ])
    |> validate_required([
      :tenant_id,
      :username,
      :normalized_username,
      :display_name,
      :access_profile,
      :status,
      :must_change_password
    ])
    |> unique_constraint([:tenant_id, :normalized_username],
      name: :platform_identity_users_tenant_username_index
    )
    |> database_constraints()
  end

  @spec activate_changeset(t()) :: Ecto.Changeset.t()
  def activate_changeset(record) do
    record
    |> change(status: "active", must_change_password: false)
    |> optimistic_lock(:lock_version)
    |> database_constraints()
  end

  defp database_constraints(changeset) do
    changeset
    |> check_constraint(:normalized_username, name: :platform_identity_users_username_check)
    |> check_constraint(:access_profile, name: :platform_identity_users_profile_check)
    |> check_constraint(:status, name: :platform_identity_users_status_check)
    |> check_constraint(:lock_version, name: :platform_identity_users_version_check)
  end
end
