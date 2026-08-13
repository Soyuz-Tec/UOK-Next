defmodule UokNext.Modules.Trade.Sourcing.Infrastructure.RfqSupplierRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "trade_rfq_suppliers" do
    field :tenant_id, :binary_id
    field :rfq_id, :binary_id
    field :supplier_party_id, :binary_id
    field :supplier_party_version, :integer
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(attrs, ~w(tenant_id rfq_id supplier_party_id supplier_party_version)a)
    |> validate_required(~w(tenant_id rfq_id supplier_party_id supplier_party_version)a)
    |> unique_constraint([:tenant_id, :rfq_id, :supplier_party_id])
    |> foreign_key_constraint(:rfq_id, name: :trade_rfq_suppliers_tenant_rfq_id_fkey)
    |> foreign_key_constraint(:supplier_party_id,
      name: :trade_rfq_suppliers_tenant_supplier_party_id_fkey
    )
    |> check_constraint(:supplier_party_version,
      name: :trade_rfq_suppliers_party_version_check
    )
  end
end
