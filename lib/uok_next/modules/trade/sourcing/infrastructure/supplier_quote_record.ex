defmodule UokNext.Modules.Trade.Sourcing.Infrastructure.SupplierQuoteRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "trade_supplier_quotes" do
    field :tenant_id, :binary_id
    field :stable_identifier, :string
    field :rfq_id, :binary_id
    field :supplier_party_id, :binary_id
    field :quoted_quantity, :decimal
    field :unit_price, :decimal
    field :currency_code, :string
    field :delivery_days, :integer
    field :status, :string, default: "draft"
    field :evidence_metadata, :map
    field :submitted_at, :utc_datetime_usec
    field :lock_version, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(
      attrs,
      ~w(tenant_id stable_identifier rfq_id supplier_party_id quoted_quantity unit_price currency_code delivery_days)a
    )
    |> validate_required(
      ~w(tenant_id stable_identifier rfq_id supplier_party_id quoted_quantity unit_price currency_code delivery_days)a
    )
    |> database_constraints()
  end

  def transition_changeset(record, attrs) do
    record
    |> cast(attrs, [:status, :evidence_metadata, :submitted_at])
    |> optimistic_lock(:lock_version)
    |> database_constraints()
  end

  defp database_constraints(changeset) do
    changeset
    |> unique_constraint([:tenant_id, :stable_identifier])
    |> unique_constraint([:tenant_id, :rfq_id, :supplier_party_id])
    |> foreign_key_constraint(:rfq_id, name: :trade_supplier_quotes_tenant_rfq_id_fkey)
    |> foreign_key_constraint(:supplier_party_id,
      name: :trade_supplier_quotes_tenant_supplier_party_id_fkey
    )
    |> check_constraint(:stable_identifier, name: :trade_supplier_quotes_identifier_check)
    |> check_constraint(:quoted_quantity, name: :trade_supplier_quotes_values_check)
    |> check_constraint(:currency_code, name: :trade_supplier_quotes_currency_check)
    |> check_constraint(:status, name: :trade_supplier_quotes_status_check)
    |> check_constraint(:status, name: :trade_supplier_quotes_lifecycle_check)
    |> check_constraint(:lock_version, name: :trade_supplier_quotes_version_check)
  end
end
