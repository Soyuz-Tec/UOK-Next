defmodule UokNext.Modules.Master.Products.Infrastructure.ProductRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "master_products" do
    field :tenant_id, :binary_id
    field :stable_identifier, :string
    field :name, :string
    field :product_kind, :string
    field :base_unit_code, :string
    field :status, :string, default: "active"
    field :lock_version, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [:tenant_id, :stable_identifier, :name, :product_kind, :base_unit_code])
    |> validate_required([:tenant_id, :stable_identifier, :name, :product_kind, :base_unit_code])
    |> unique_constraint([:tenant_id, :stable_identifier],
      name: :master_products_tenant_stable_identifier_index
    )
    |> check_constraint(:stable_identifier, name: :master_products_identifier_check)
    |> check_constraint(:product_kind, name: :master_products_kind_check)
    |> check_constraint(:base_unit_code, name: :master_products_unit_code_check)
    |> check_constraint(:status, name: :master_products_status_check)
    |> check_constraint(:lock_version, name: :master_products_version_check)
  end
end
