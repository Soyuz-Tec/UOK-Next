defmodule UokNext.Modules.Trade.Sourcing.Infrastructure.SourcingLaneRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "trade_sourcing_lanes" do
    field :tenant_id, :binary_id
    field :stable_identifier, :string
    field :name, :string
    field :supplier_party_id, :binary_id
    field :product_id, :binary_id
    field :origin_location_id, :binary_id
    field :destination_location_id, :binary_id
    field :status, :string, default: "draft"
    field :evidence_metadata, :map
    field :evidence_submitted_at, :utc_datetime_usec
    field :decision_reason, :string
    field :decision_actor_id, :binary_id
    field :decided_at, :utc_datetime_usec
    field :lock_version, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :tenant_id,
      :stable_identifier,
      :name,
      :supplier_party_id,
      :product_id,
      :origin_location_id,
      :destination_location_id
    ])
    |> validate_required([
      :tenant_id,
      :stable_identifier,
      :name,
      :supplier_party_id,
      :product_id,
      :origin_location_id,
      :destination_location_id
    ])
    |> unique_constraint([:tenant_id, :stable_identifier],
      name: :trade_sourcing_lanes_tenant_stable_identifier_index
    )
    |> foreign_keys()
    |> database_constraints()
  end

  @spec transition_changeset(t(), map()) :: Ecto.Changeset.t()
  def transition_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :status,
      :evidence_metadata,
      :evidence_submitted_at,
      :decision_reason,
      :decision_actor_id,
      :decided_at
    ])
    |> optimistic_lock(:lock_version)
    |> database_constraints()
  end

  defp foreign_keys(changeset) do
    changeset
    |> foreign_key_constraint(:supplier_party_id,
      name: :trade_sourcing_lanes_tenant_supplier_fkey
    )
    |> foreign_key_constraint(:product_id, name: :trade_sourcing_lanes_tenant_product_fkey)
    |> foreign_key_constraint(:origin_location_id,
      name: :trade_sourcing_lanes_tenant_origin_fkey
    )
    |> foreign_key_constraint(:destination_location_id,
      name: :trade_sourcing_lanes_tenant_destination_fkey
    )
  end

  defp database_constraints(changeset) do
    changeset
    |> check_constraint(:stable_identifier, name: :trade_sourcing_lanes_identifier_check)
    |> check_constraint(:status, name: :trade_sourcing_lanes_status_check)
    |> check_constraint(:destination_location_id, name: :trade_sourcing_lanes_route_check)
    |> check_constraint(:lock_version, name: :trade_sourcing_lanes_version_check)
    |> check_constraint(:status, name: :trade_sourcing_lanes_lifecycle_check)
  end
end
