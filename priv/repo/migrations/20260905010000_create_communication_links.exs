defmodule UokNext.Repo.Migrations.CreateCommunicationLinks do
  use Ecto.Migration

  def up do
    create table(:platform_integrations_communication_links, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :subject_type, :string, size: 32, null: false
      add :subject_id, :uuid, null: false
      add :subject_version, :integer, null: false
      add :conversation_id, :uuid, null: false
      add :created_by_actor_id, :uuid, null: false
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(
             :platform_integrations_communication_links,
             [:tenant_id, :subject_id, :subject_version, :conversation_id],
             name: :platform_integrations_communication_links_binding_index
           )

    execute """
    ALTER TABLE platform_integrations_communication_links
    ADD CONSTRAINT platform_integrations_communication_links_party_fkey
    FOREIGN KEY (tenant_id, subject_id) REFERENCES master_parties (tenant_id, id)
    ON DELETE RESTRICT
    """

    create constraint(
             :platform_integrations_communication_links,
             :platform_integrations_communication_links_shape_check,
             check: "subject_type = 'party' AND subject_version > 0 AND lock_version = 1"
           )

    execute "ALTER TABLE platform_integrations_communication_links ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE platform_integrations_communication_links FORCE ROW LEVEL SECURITY"

    execute """
    CREATE POLICY platform_integrations_communication_links_tenant_isolation
    ON platform_integrations_communication_links
    USING (tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid)
    WITH CHECK (tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid)
    """
  end

  def down do
    drop table(:platform_integrations_communication_links)
  end
end
