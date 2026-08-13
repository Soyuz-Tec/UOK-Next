defmodule UokNext.Modules.Trade.Contracts.Infrastructure.PurchaseCommitmentProposalRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "trade_purchase_commitment_proposals" do
    field :tenant_id, :binary_id
    field :stable_identifier, :string
    field :quote_comparison_id, :binary_id
    field :quote_comparison_version, :integer
    field :selected_quote_id, :binary_id
    field :selected_quote_version, :integer
    field :source_snapshot, :map
    field :status, :string, default: "draft"
    field :evidence_metadata, :map
    field :proposed_by_actor_id, :binary_id
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
      ~w(tenant_id stable_identifier quote_comparison_id quote_comparison_version selected_quote_id selected_quote_version source_snapshot proposed_by_actor_id)a
    )
    |> validate_required(
      ~w(tenant_id stable_identifier quote_comparison_id quote_comparison_version selected_quote_id selected_quote_version source_snapshot proposed_by_actor_id)a
    )
    |> database_constraints()
  end

  def transition_changeset(record, attrs) do
    record
    |> cast(
      attrs,
      ~w(status evidence_metadata submitted_at decision_reason decision_actor_id decided_at)a
    )
    |> optimistic_lock(:lock_version)
    |> database_constraints()
  end

  defp database_constraints(changeset) do
    changeset
    |> unique_constraint([:tenant_id, :stable_identifier],
      name: :trade_commitment_proposals_identifier_index
    )
    |> unique_constraint([:tenant_id, :quote_comparison_id],
      name: :trade_commitment_proposals_comparison_index
    )
    |> foreign_key_constraint(:quote_comparison_id,
      name: :trade_commitment_proposals_quote_comparison_id_fkey
    )
    |> foreign_key_constraint(:selected_quote_id,
      name: :trade_commitment_proposals_selected_quote_id_fkey
    )
    |> foreign_key_constraint(:selected_quote_id,
      name: :trade_commitment_proposals_source_quote_fkey
    )
    |> check_constraint(:stable_identifier,
      name: :trade_purchase_commitment_proposals_identifier_check
    )
    |> check_constraint(:quote_comparison_version,
      name: :trade_purchase_commitment_proposals_source_version_check
    )
    |> check_constraint(:source_snapshot,
      name: :trade_purchase_commitment_proposals_snapshot_check
    )
    |> check_constraint(:evidence_metadata,
      name: :trade_purchase_commitment_proposals_evidence_size_check
    )
    |> check_constraint(:status, name: :trade_purchase_commitment_proposals_status_check)
    |> check_constraint(:status, name: :trade_purchase_commitment_proposals_lifecycle_check)
    |> check_constraint(:lock_version, name: :trade_purchase_commitment_proposals_version_check)
  end
end
