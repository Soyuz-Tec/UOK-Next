defmodule UokNext.Modules.Master.Locations.Infrastructure.LocationRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "master_locations" do
    field :tenant_id, :binary_id
    field :stable_identifier, :string
    field :name, :string
    field :country_code, :string
    field :location_kind, :string
    field :status, :string, default: "active"
    field :lock_version, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [:tenant_id, :stable_identifier, :name, :country_code, :location_kind])
    |> validate_required([:tenant_id, :stable_identifier, :name, :country_code, :location_kind])
    |> unique_constraint([:tenant_id, :stable_identifier],
      name: :master_locations_tenant_stable_identifier_index
    )
    |> check_constraint(:stable_identifier, name: :master_locations_identifier_check)
    |> check_constraint(:country_code, name: :master_locations_country_code_check)
    |> check_constraint(:location_kind, name: :master_locations_kind_check)
    |> check_constraint(:status, name: :master_locations_status_check)
    |> check_constraint(:lock_version, name: :master_locations_version_check)
  end
end
