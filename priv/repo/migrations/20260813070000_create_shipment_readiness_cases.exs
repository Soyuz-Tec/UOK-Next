defmodule UokNext.Repo.Migrations.CreateShipmentReadinessCases do
  @moduledoc "Owned by trade.shipments; forward migration for ADR-0021."

  use Ecto.Migration

  @table :trade_shipment_readiness_cases

  def up do
    create table(@table, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :stable_identifier, :string, null: false, size: 100
      add :purchase_commitment_proposal_id, :uuid, null: false
      add :purchase_commitment_proposal_version, :integer, null: false
      add :source_snapshot, :map, null: false
      add :checklist_snapshot, :map, null: false
      add :status, :string, null: false, size: 24, default: "draft"
      add :evidence_metadata, :map
      add :created_by_actor_id, :uuid, null: false
      add :submitted_at, :utc_datetime_usec
      add :decision_reason, :string, size: 500
      add :decision_actor_id, :uuid
      add :decided_at, :utc_datetime_usec
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(@table, [:tenant_id, :id])

    create unique_index(@table, [:tenant_id, :stable_identifier],
             name: :trade_readiness_cases_identifier_index
           )

    create unique_index(@table, [:tenant_id, :purchase_commitment_proposal_id],
             name: :trade_readiness_cases_proposal_index
           )

    create constraint(@table, :trade_shipment_readiness_cases_identifier_check,
             check: "stable_identifier ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{2,99}$'"
           )

    create constraint(@table, :trade_shipment_readiness_cases_source_version_check,
             check: "purchase_commitment_proposal_version > 0"
           )

    create constraint(@table, :trade_shipment_readiness_cases_source_check,
             check:
               "jsonb_typeof(source_snapshot) = 'object' AND " <>
                 "octet_length(source_snapshot::text) BETWEEN 2 AND 24576"
           )

    create constraint(@table, :trade_shipment_readiness_cases_checklist_check,
             check:
               "jsonb_typeof(checklist_snapshot) = 'object' AND " <>
                 "octet_length(checklist_snapshot::text) BETWEEN 2 AND 8192"
           )

    create constraint(@table, :trade_shipment_readiness_cases_evidence_check,
             check:
               "evidence_metadata IS NULL OR " <>
                 "(jsonb_typeof(evidence_metadata) = 'object' AND " <>
                 "octet_length(evidence_metadata::text) BETWEEN 2 AND 2048)"
           )

    create constraint(@table, :trade_shipment_readiness_cases_status_check,
             check: "status IN ('draft', 'awaiting_review', 'go', 'hold')"
           )

    create constraint(@table, :trade_shipment_readiness_cases_lifecycle_check,
             check:
               "(status = 'draft' AND evidence_metadata IS NULL AND submitted_at IS NULL AND " <>
                 "decision_reason IS NULL AND decision_actor_id IS NULL AND decided_at IS NULL) OR " <>
                 "(status = 'awaiting_review' AND evidence_metadata IS NOT NULL AND " <>
                 "submitted_at IS NOT NULL AND decision_reason IS NULL AND " <>
                 "decision_actor_id IS NULL AND decided_at IS NULL) OR " <>
                 "(status IN ('go', 'hold') AND evidence_metadata IS NOT NULL AND " <>
                 "submitted_at IS NOT NULL AND decision_reason IS NOT NULL AND " <>
                 "decision_actor_id IS NOT NULL AND decided_at IS NOT NULL)"
           )

    create constraint(@table, :trade_shipment_readiness_cases_version_check,
             check: "lock_version > 0"
           )

    add_references()
    enable_tenant_isolation()
  end

  def down do
    execute "DROP POLICY IF EXISTS trade_shipment_readiness_cases_tenant_isolation ON #{@table}"
    drop table(@table)
  end

  defp add_references do
    execute """
    ALTER TABLE #{@table}
    ADD CONSTRAINT trade_readiness_cases_proposal_fkey
    FOREIGN KEY (tenant_id, purchase_commitment_proposal_id)
    REFERENCES trade_purchase_commitment_proposals (tenant_id, id)
    ON DELETE RESTRICT
    """
  end

  defp enable_tenant_isolation do
    execute "ALTER TABLE #{@table} ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE #{@table} FORCE ROW LEVEL SECURITY"

    execute """
    CREATE POLICY trade_shipment_readiness_cases_tenant_isolation ON #{@table}
    USING (tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid)
    WITH CHECK (tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid)
    """
  end
end
