defmodule UokNext.Repo.Migrations.CreateConnectorReceipts do
  use Ecto.Migration

  def up do
    create table(:platform_integrations_connector_receipts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :connector_role, :string, null: false, size: 120
      add :operation, :string, null: false, size: 120
      add :delivery_key, :string, null: false, size: 128
      add :attempt_number, :integer, null: false
      add :request_sha256, :string, null: false, size: 64
      add :subject_type, :string, null: false, size: 120
      add :subject_id, :uuid, null: false
      add :subject_version, :integer, null: false
      add :status, :string, null: false, size: 32, default: "attempted"
      add :timeout_ms, :integer, null: false
      add :deadline_at, :utc_datetime_usec, null: false
      add :previous_receipt_id, :uuid
      add :response_sha256, :string, size: 64
      add :external_reference, :string, size: 200
      add :retry_after_seconds, :integer
      add :outcome_reason, :string, size: 500
      add :attempted_by_actor_id, :uuid, null: false
      add :attempted_at, :utc_datetime_usec, null: false
      add :reconciled_by_actor_id, :uuid
      add :reconciled_at, :utc_datetime_usec
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:platform_integrations_connector_receipts, [:tenant_id, :id],
             name: :platform_integrations_connector_receipts_tenant_identity_index
           )

    create unique_index(
             :platform_integrations_connector_receipts,
             [:tenant_id, :connector_role, :delivery_key, :attempt_number],
             name: :platform_integrations_connector_receipts_delivery_attempt_index
           )

    create index(
             :platform_integrations_connector_receipts,
             [:tenant_id, :status, :deadline_at],
             name: :platform_integrations_connector_receipts_reconciliation_index
           )

    execute """
    ALTER TABLE platform_integrations_connector_receipts
    ADD CONSTRAINT platform_integrations_connector_receipts_previous_fkey
    FOREIGN KEY (tenant_id, previous_receipt_id)
    REFERENCES platform_integrations_connector_receipts (tenant_id, id)
    ON DELETE RESTRICT
    """

    create constraint(
             :platform_integrations_connector_receipts,
             :platform_integrations_connector_receipts_identifier_check,
             check: """
             connector_role ~ '^[a-z][a-z0-9_.:-]{2,119}$' AND
             operation ~ '^[a-z][a-z0-9_.:-]{2,119}$' AND
             subject_type ~ '^[a-z][a-z0-9_.:-]{1,119}$' AND
             delivery_key ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$'
             """
           )

    create constraint(
             :platform_integrations_connector_receipts,
             :platform_integrations_connector_receipts_digest_check,
             check: """
             request_sha256 ~ '^[0-9a-f]{64}$' AND
             (response_sha256 IS NULL OR response_sha256 ~ '^[0-9a-f]{64}$')
             """
           )

    create constraint(
             :platform_integrations_connector_receipts,
             :platform_integrations_connector_receipts_version_check,
             check: """
             subject_version > 0 AND lock_version > 0 AND
             timeout_ms BETWEEN 100 AND 120000 AND
             retry_after_seconds BETWEEN 0 AND 86400
             """
           )

    create constraint(
             :platform_integrations_connector_receipts,
             :platform_integrations_connector_receipts_retry_lineage_check,
             check: """
             (previous_receipt_id IS NULL AND attempt_number = 1) OR
             (previous_receipt_id IS NOT NULL AND attempt_number > 1)
             """
           )

    create constraint(
             :platform_integrations_connector_receipts,
             :platform_integrations_connector_receipts_lifecycle_check,
             check: """
             (status = 'attempted' AND response_sha256 IS NULL AND
              external_reference IS NULL AND retry_after_seconds IS NULL AND
              outcome_reason IS NULL AND reconciled_by_actor_id IS NULL AND
              reconciled_at IS NULL) OR
             (status = 'succeeded' AND response_sha256 IS NOT NULL AND
              retry_after_seconds IS NULL AND outcome_reason IS NOT NULL AND
              reconciled_by_actor_id IS NOT NULL AND reconciled_at IS NOT NULL) OR
             (status = 'retryable_failure' AND external_reference IS NULL AND
              retry_after_seconds IS NOT NULL AND outcome_reason IS NOT NULL AND
              reconciled_by_actor_id IS NOT NULL AND reconciled_at IS NOT NULL) OR
             (status = 'permanent_failure' AND external_reference IS NULL AND
              retry_after_seconds IS NULL AND outcome_reason IS NOT NULL AND
              reconciled_by_actor_id IS NOT NULL AND reconciled_at IS NOT NULL) OR
             (status = 'timed_out' AND response_sha256 IS NULL AND
              external_reference IS NULL AND retry_after_seconds IS NOT NULL AND
              outcome_reason IS NOT NULL AND reconciled_by_actor_id IS NOT NULL AND
              reconciled_at IS NOT NULL)
             """
           )

    execute "ALTER TABLE platform_integrations_connector_receipts ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE platform_integrations_connector_receipts FORCE ROW LEVEL SECURITY"

    execute """
    CREATE POLICY platform_integrations_connector_receipts_tenant_isolation
    ON platform_integrations_connector_receipts
    USING (tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid)
    WITH CHECK (tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid)
    """
  end

  def down do
    execute "DROP POLICY IF EXISTS platform_integrations_connector_receipts_tenant_isolation ON platform_integrations_connector_receipts"
    drop table(:platform_integrations_connector_receipts)
  end
end
