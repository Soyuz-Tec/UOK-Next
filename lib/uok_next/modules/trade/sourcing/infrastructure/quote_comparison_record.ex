defmodule UokNext.Modules.Trade.Sourcing.Infrastructure.QuoteComparisonRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "trade_quote_comparisons" do
    field :tenant_id, :binary_id
    field :stable_identifier, :string
    field :rfq_id, :binary_id
    field :rfq_version, :integer
    field :recommended_quote_id, :binary_id
    field :ranking_snapshot, :map
    field :status, :string, default: "awaiting_review"
    field :decision_reason, :string
    field :decision_actor_id, :binary_id
    field :decided_at, :utc_datetime_usec
    field :lock_version, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(
      attrs,
      ~w(tenant_id stable_identifier rfq_id rfq_version recommended_quote_id ranking_snapshot)a
    )
    |> validate_required(
      ~w(tenant_id stable_identifier rfq_id rfq_version recommended_quote_id ranking_snapshot)a
    )
    |> database_constraints()
  end

  def transition_changeset(record, attrs) do
    record
    |> cast(attrs, [:status, :decision_reason, :decision_actor_id, :decided_at])
    |> optimistic_lock(:lock_version)
    |> database_constraints()
  end

  defp database_constraints(changeset) do
    changeset
    |> unique_constraint([:tenant_id, :stable_identifier])
    |> unique_constraint([:tenant_id, :rfq_id])
    |> foreign_key_constraint(:rfq_id, name: :trade_quote_comparisons_tenant_rfq_id_fkey)
    |> foreign_key_constraint(:recommended_quote_id,
      name: :trade_quote_comparisons_tenant_recommended_quote_id_fkey
    )
    |> foreign_key_constraint(:recommended_quote_id,
      name: :trade_quote_comparisons_tenant_rfq_recommended_quote_fkey
    )
    |> check_constraint(:stable_identifier, name: :trade_quote_comparisons_identifier_check)
    |> check_constraint(:status, name: :trade_quote_comparisons_status_check)
    |> check_constraint(:status, name: :trade_quote_comparisons_lifecycle_check)
    |> check_constraint(:rfq_version, name: :trade_quote_comparisons_source_version_check)
    |> check_constraint(:lock_version, name: :trade_quote_comparisons_version_check)
  end
end
