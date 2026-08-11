defmodule UokNext.Repo.Migrations.CreatePartyOnboardingKernel do
  use Ecto.Migration

  def up do
    create table(:kernel_command_receipts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :actor_id, :uuid, null: false
      add :correlation_id, :uuid, null: false
      add :idempotency_key, :string, null: false, size: 128
      add :command_name, :string, null: false, size: 160
      add :payload_hash, :binary, null: false
      add :status, :string, null: false, size: 24
      add :response, :map
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:kernel_command_receipts, [:tenant_id, :idempotency_key],
             name: :kernel_command_receipts_tenant_idempotency_index
           )

    create constraint(:kernel_command_receipts, :kernel_command_receipts_status_check,
             check: "status IN ('executing', 'completed')"
           )

    create table(:kernel_audit_events, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :actor_id, :uuid, null: false
      add :correlation_id, :uuid, null: false

      add :command_receipt_id,
          references(:kernel_command_receipts, type: :uuid, on_delete: :restrict),
          null: false

      add :action, :string, null: false, size: 160
      add :resource_type, :string, null: false, size: 120
      add :resource_id, :uuid, null: false
      add :outcome, :string, null: false, size: 32
      add :reason, :string, null: false, size: 500
      add :classification, :string, null: false, size: 32
      add :metadata, :map, null: false, default: %{}
      add :occurred_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:kernel_audit_events, [:tenant_id, :resource_type, :resource_id, :occurred_at],
             name: :kernel_audit_events_resource_timeline_index
           )

    create table(:kernel_outbox_events, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :actor_id, :uuid, null: false
      add :correlation_id, :uuid, null: false

      add :command_receipt_id,
          references(:kernel_command_receipts, type: :uuid, on_delete: :restrict),
          null: false

      add :event_name, :string, null: false, size: 160
      add :event_version, :integer, null: false
      add :aggregate_type, :string, null: false, size: 120
      add :aggregate_id, :uuid, null: false
      add :aggregate_version, :integer, null: false
      add :classification, :string, null: false, size: 32
      add :payload, :map, null: false
      add :status, :string, null: false, size: 24, default: "pending"
      add :available_at, :utc_datetime_usec, null: false
      add :published_at, :utc_datetime_usec
      add :attempt_count, :integer, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create index(:kernel_outbox_events, [:status, :available_at],
             name: :kernel_outbox_events_delivery_index
           )

    create index(:kernel_outbox_events, [:tenant_id, :aggregate_type, :aggregate_id],
             name: :kernel_outbox_events_aggregate_index
           )

    create constraint(:kernel_outbox_events, :kernel_outbox_events_status_check,
             check: "status IN ('pending', 'publishing', 'published', 'dead_letter')"
           )

    create constraint(:kernel_outbox_events, :kernel_outbox_events_version_check,
             check: "event_version > 0 AND aggregate_version > 0 AND attempt_count >= 0"
           )

    create table(:master_parties, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :stable_identifier, :string, null: false, size: 100
      add :legal_name, :string, null: false, size: 200
      add :country_code, :string, null: false, size: 2
      add :party_kind, :string, null: false, size: 32
      add :status, :string, null: false, size: 32, default: "draft"
      add :evidence_metadata, :map
      add :evidence_submitted_at, :utc_datetime_usec
      add :decision_reason, :string, size: 500
      add :decision_actor_id, :uuid
      add :decided_at, :utc_datetime_usec
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:master_parties, [:tenant_id, :stable_identifier],
             name: :master_parties_tenant_stable_identifier_index
           )

    create index(:master_parties, [:tenant_id, :status],
             name: :master_parties_tenant_status_index
           )

    create constraint(:master_parties, :master_parties_country_code_check,
             check: "country_code ~ '^[A-Z]{2}$'"
           )

    create constraint(:master_parties, :master_parties_kind_check,
             check: "party_kind IN ('organization', 'individual')"
           )

    create constraint(:master_parties, :master_parties_status_check,
             check: "status IN ('draft', 'evidence_submitted', 'approved', 'hold')"
           )

    create constraint(:master_parties, :master_parties_lock_version_check,
             check: "lock_version > 0"
           )

    execute """
    CREATE FUNCTION uok_prevent_audit_event_mutation()
    RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'kernel audit events are append-only';
    END;
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE TRIGGER kernel_audit_events_append_only
    BEFORE UPDATE OR DELETE ON kernel_audit_events
    FOR EACH ROW EXECUTE FUNCTION uok_prevent_audit_event_mutation()
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS kernel_audit_events_append_only ON kernel_audit_events"
    execute "DROP FUNCTION IF EXISTS uok_prevent_audit_event_mutation()"
    drop table(:master_parties)
    drop table(:kernel_outbox_events)
    drop table(:kernel_audit_events)
    drop table(:kernel_command_receipts)
  end
end
