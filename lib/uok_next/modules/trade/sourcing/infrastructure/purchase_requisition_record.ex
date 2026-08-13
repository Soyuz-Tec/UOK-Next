defmodule UokNext.Modules.Trade.Sourcing.Infrastructure.PurchaseRequisitionRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "trade_purchase_requisitions" do
    field :tenant_id, :binary_id
    field :stable_identifier, :string
    field :sourcing_lane_id, :binary_id
    field :sourcing_lane_version, :integer
    field :quantity, :decimal
    field :unit_code, :string
    field :required_by, :date
    field :status, :string, default: "ready_for_rfq"
    field :lock_version, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(
      attrs,
      ~w(tenant_id stable_identifier sourcing_lane_id sourcing_lane_version quantity unit_code required_by)a
    )
    |> validate_required(
      ~w(tenant_id stable_identifier sourcing_lane_id sourcing_lane_version quantity unit_code required_by)a
    )
    |> database_constraints()
  end

  def transition_changeset(record, attrs) do
    record |> cast(attrs, [:status]) |> optimistic_lock(:lock_version) |> database_constraints()
  end

  defp database_constraints(changeset) do
    changeset
    |> unique_constraint([:tenant_id, :stable_identifier])
    |> foreign_key_constraint(:sourcing_lane_id,
      name: :trade_purchase_requisitions_tenant_sourcing_lane_id_fkey
    )
    |> check_constraint(:stable_identifier, name: :trade_purchase_requisitions_identifier_check)
    |> check_constraint(:quantity, name: :trade_purchase_requisitions_quantity_check)
    |> check_constraint(:unit_code, name: :trade_purchase_requisitions_unit_check)
    |> check_constraint(:status, name: :trade_purchase_requisitions_status_check)
    |> check_constraint(:sourcing_lane_version,
      name: :trade_purchase_requisitions_source_version_check
    )
    |> check_constraint(:lock_version, name: :trade_purchase_requisitions_version_check)
  end
end
