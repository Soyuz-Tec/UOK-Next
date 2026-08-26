defmodule UokNext.Repo.Migrations.CreateBootstrapSessions do
  use Ecto.Migration

  @table "platform_identity_bootstrap_sessions"

  def up do
    create table(:platform_identity_bootstrap_sessions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :actor_id, :uuid, null: false
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :revoked_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:platform_identity_bootstrap_sessions, [:tenant_id, :token_hash],
             name: :platform_identity_bootstrap_sessions_tenant_token_index
           )

    create index(:platform_identity_bootstrap_sessions, [:tenant_id, :actor_id, :expires_at],
             name: :platform_identity_bootstrap_sessions_actor_expiry_index
           )

    create constraint(
             :platform_identity_bootstrap_sessions,
             :platform_identity_bootstrap_sessions_token_hash_check,
             check: "octet_length(token_hash) = 32"
           )

    execute("ALTER TABLE #{@table} ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE #{@table} FORCE ROW LEVEL SECURITY")

    execute("""
    CREATE POLICY #{@table}_tenant_isolation ON #{@table}
    USING (tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid)
    WITH CHECK (tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid)
    """)
  end

  def down do
    execute("DROP POLICY IF EXISTS #{@table}_tenant_isolation ON #{@table}")
    execute("ALTER TABLE #{@table} NO FORCE ROW LEVEL SECURITY")
    execute("ALTER TABLE #{@table} DISABLE ROW LEVEL SECURITY")
    drop table(:platform_identity_bootstrap_sessions)
  end
end
