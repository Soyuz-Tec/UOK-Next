defmodule UokNext.Repo.Migrations.CreatePurchaseCommitmentProposals do
  @moduledoc "Owned by trade.contracts; forward migration for ADR-0020."

  use Ecto.Migration

  @table :trade_purchase_commitment_proposals

  def up do
    create table(@table, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :stable_identifier, :string, null: false, size: 100
      add :quote_comparison_id, :uuid, null: false
      add :quote_comparison_version, :integer, null: false
      add :selected_quote_id, :uuid, null: false
      add :selected_quote_version, :integer, null: false
      add :source_snapshot, :map, null: false
      add :status, :string, null: false, size: 24, default: "draft"
      add :evidence_metadata, :map
      add :proposed_by_actor_id, :uuid, null: false
      add :submitted_at, :utc_datetime_usec
      add :decision_reason, :string, size: 500
      add :decision_actor_id, :uuid
      add :decided_at, :utc_datetime_usec
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(@table, [:tenant_id, :id])

    create unique_index(@table, [:tenant_id, :stable_identifier],
             name: :trade_commitment_proposals_identifier_index
           )

    create unique_index(@table, [:tenant_id, :quote_comparison_id],
             name: :trade_commitment_proposals_comparison_index
           )

    create index(@table, [:tenant_id, :selected_quote_id],
             name: :trade_commitment_proposals_selected_quote_index
           )

    create constraint(@table, :trade_purchase_commitment_proposals_identifier_check,
             check: "stable_identifier ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{2,99}$'"
           )

    create constraint(@table, :trade_purchase_commitment_proposals_source_version_check,
             check: "quote_comparison_version > 0 AND selected_quote_version > 0"
           )

    create constraint(@table, :trade_purchase_commitment_proposals_snapshot_check,
             check:
               "jsonb_typeof(source_snapshot) = 'object' AND " <>
                 "octet_length(source_snapshot::text) BETWEEN 2 AND 16384"
           )

    create constraint(@table, :trade_purchase_commitment_proposals_evidence_size_check,
             check:
               "evidence_metadata IS NULL OR " <>
                 "(jsonb_typeof(evidence_metadata) = 'object' AND " <>
                 "octet_length(evidence_metadata::text) BETWEEN 2 AND 2048)"
           )

    create constraint(@table, :trade_purchase_commitment_proposals_status_check,
             check: "status IN ('draft', 'awaiting_review', 'approved', 'hold')"
           )

    create constraint(@table, :trade_purchase_commitment_proposals_lifecycle_check,
             check:
               "(status = 'draft' AND evidence_metadata IS NULL AND submitted_at IS NULL AND " <>
                 "decision_reason IS NULL AND decision_actor_id IS NULL AND decided_at IS NULL) OR " <>
                 "(status = 'awaiting_review' AND evidence_metadata IS NOT NULL AND " <>
                 "submitted_at IS NOT NULL AND decision_reason IS NULL AND " <>
                 "decision_actor_id IS NULL AND decided_at IS NULL) OR " <>
                 "(status IN ('approved', 'hold') AND evidence_metadata IS NOT NULL AND " <>
                 "submitted_at IS NOT NULL AND decision_reason IS NOT NULL AND " <>
                 "decision_actor_id IS NOT NULL AND decided_at IS NOT NULL)"
           )

    create constraint(@table, :trade_purchase_commitment_proposals_version_check,
             check: "lock_version > 0"
           )

    add_references()
    enable_tenant_isolation()
  end

  def down do
    execute "DROP POLICY IF EXISTS trade_purchase_commitment_proposals_tenant_isolation ON #{@table}"
    drop table(@table)
  end

  defp add_references do
    tenant_fk(:quote_comparison_id, :trade_quote_comparisons)
    tenant_fk(:selected_quote_id, :trade_supplier_quotes)

    execute """
    ALTER TABLE #{@table}
    ADD CONSTRAINT trade_commitment_proposals_source_quote_fkey
    FOREIGN KEY (tenant_id, quote_comparison_id, selected_quote_id)
    REFERENCES trade_quote_comparisons (tenant_id, id, recommended_quote_id)
    ON DELETE RESTRICT
    """
  end

  defp tenant_fk(column, referenced_table) do
    execute """
    ALTER TABLE #{@table}
    ADD CONSTRAINT trade_commitment_proposals_#{column}_fkey
    FOREIGN KEY (tenant_id, #{column})
    REFERENCES #{referenced_table} (tenant_id, id)
    ON DELETE RESTRICT
    """
  end

  defp enable_tenant_isolation do
    execute "ALTER TABLE #{@table} ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE #{@table} FORCE ROW LEVEL SECURITY"

    execute """
    CREATE POLICY trade_purchase_commitment_proposals_tenant_isolation ON #{@table}
    USING (tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid)
    WITH CHECK (tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid)
    """
  end
end
