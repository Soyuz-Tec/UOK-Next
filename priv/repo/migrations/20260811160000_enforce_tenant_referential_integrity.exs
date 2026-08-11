defmodule UokNext.Repo.Migrations.EnforceTenantReferentialIntegrity do
  use Ecto.Migration

  def up do
    create unique_index(:kernel_command_receipts, [:tenant_id, :id],
             name: :kernel_command_receipts_tenant_identity_index
           )

    drop constraint(:kernel_audit_events, :kernel_audit_events_command_receipt_id_fkey)
    drop constraint(:kernel_outbox_events, :kernel_outbox_events_command_receipt_id_fkey)

    execute """
    ALTER TABLE kernel_audit_events
    ADD CONSTRAINT kernel_audit_events_tenant_receipt_fkey
    FOREIGN KEY (tenant_id, command_receipt_id)
    REFERENCES kernel_command_receipts (tenant_id, id)
    ON DELETE RESTRICT
    NOT VALID
    """

    execute """
    ALTER TABLE kernel_outbox_events
    ADD CONSTRAINT kernel_outbox_events_tenant_receipt_fkey
    FOREIGN KEY (tenant_id, command_receipt_id)
    REFERENCES kernel_command_receipts (tenant_id, id)
    ON DELETE RESTRICT
    NOT VALID
    """

    execute "ALTER TABLE kernel_audit_events VALIDATE CONSTRAINT kernel_audit_events_tenant_receipt_fkey"

    execute "ALTER TABLE kernel_outbox_events VALIDATE CONSTRAINT kernel_outbox_events_tenant_receipt_fkey"
  end

  def down do
    drop constraint(:kernel_audit_events, :kernel_audit_events_tenant_receipt_fkey)
    drop constraint(:kernel_outbox_events, :kernel_outbox_events_tenant_receipt_fkey)

    alter table(:kernel_audit_events) do
      modify :command_receipt_id,
             references(:kernel_command_receipts, type: :uuid, on_delete: :restrict),
             from: :uuid
    end

    alter table(:kernel_outbox_events) do
      modify :command_receipt_id,
             references(:kernel_command_receipts, type: :uuid, on_delete: :restrict),
             from: :uuid
    end

    drop index(:kernel_command_receipts, [:tenant_id, :id],
           name: :kernel_command_receipts_tenant_identity_index
         )
  end
end
