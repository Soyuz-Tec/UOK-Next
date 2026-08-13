defmodule UokNext.Modules.Trade.Shipments.Infrastructure.ShipmentReadinessCaseRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "trade_shipment_readiness_cases" do
    field :tenant_id, :binary_id
    field :stable_identifier, :string
    field :purchase_commitment_proposal_id, :binary_id
    field :purchase_commitment_proposal_version, :integer
    field :source_snapshot, :map
    field :checklist_snapshot, :map
    field :status, :string, default: "draft"
    field :evidence_metadata, :map
    field :created_by_actor_id, :binary_id
    field :submitted_at, :utc_datetime_usec
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
      ~w(tenant_id stable_identifier purchase_commitment_proposal_id purchase_commitment_proposal_version source_snapshot checklist_snapshot created_by_actor_id)a
    )
    |> validate_required(
      ~w(tenant_id stable_identifier purchase_commitment_proposal_id purchase_commitment_proposal_version source_snapshot checklist_snapshot created_by_actor_id)a
    )
    |> database_constraints()
  end

  def transition_changeset(record, attrs) do
    record
    |> cast(
      attrs,
      ~w(status checklist_snapshot evidence_metadata submitted_at decision_reason decision_actor_id decided_at)a
    )
    |> optimistic_lock(:lock_version)
    |> database_constraints()
  end

  defp database_constraints(changeset) do
    changeset
    |> unique_constraint([:tenant_id, :stable_identifier],
      name: :trade_readiness_cases_identifier_index
    )
    |> unique_constraint([:tenant_id, :purchase_commitment_proposal_id],
      name: :trade_readiness_cases_proposal_index
    )
    |> foreign_key_constraint(:purchase_commitment_proposal_id,
      name: :trade_readiness_cases_proposal_fkey
    )
    |> check_constraint(:stable_identifier,
      name: :trade_shipment_readiness_cases_identifier_check
    )
    |> check_constraint(:purchase_commitment_proposal_version,
      name: :trade_shipment_readiness_cases_source_version_check
    )
    |> check_constraint(:source_snapshot, name: :trade_shipment_readiness_cases_source_check)
    |> check_constraint(:checklist_snapshot,
      name: :trade_shipment_readiness_cases_checklist_check
    )
    |> check_constraint(:evidence_metadata, name: :trade_shipment_readiness_cases_evidence_check)
    |> check_constraint(:status, name: :trade_shipment_readiness_cases_status_check)
    |> check_constraint(:status, name: :trade_shipment_readiness_cases_lifecycle_check)
    |> check_constraint(:lock_version, name: :trade_shipment_readiness_cases_version_check)
  end
end
