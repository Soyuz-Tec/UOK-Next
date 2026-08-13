defmodule UokNext.Modules.Trade.Sourcing.Infrastructure.RfqRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "trade_rfqs" do
    field :tenant_id, :binary_id
    field :stable_identifier, :string
    field :requisition_id, :binary_id
    field :requisition_version, :integer
    field :settlement_currency_code, :string
    field :response_deadline, :utc_datetime_usec
    field :status, :string, default: "open"
    field :lock_version, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(
      attrs,
      ~w(tenant_id stable_identifier requisition_id requisition_version settlement_currency_code response_deadline)a
    )
    |> validate_required(
      ~w(tenant_id stable_identifier requisition_id requisition_version settlement_currency_code response_deadline)a
    )
    |> database_constraints()
  end

  def transition_changeset(record, attrs) do
    record |> cast(attrs, [:status]) |> optimistic_lock(:lock_version) |> database_constraints()
  end

  defp database_constraints(changeset) do
    changeset
    |> unique_constraint([:tenant_id, :stable_identifier])
    |> unique_constraint([:tenant_id, :requisition_id])
    |> foreign_key_constraint(:requisition_id, name: :trade_rfqs_tenant_requisition_id_fkey)
    |> check_constraint(:stable_identifier, name: :trade_rfqs_identifier_check)
    |> check_constraint(:settlement_currency_code, name: :trade_rfqs_currency_check)
    |> check_constraint(:status, name: :trade_rfqs_status_check)
    |> check_constraint(:requisition_version, name: :trade_rfqs_source_version_check)
    |> check_constraint(:lock_version, name: :trade_rfqs_version_check)
  end
end
