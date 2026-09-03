defmodule UokNext.Repo.Migrations.CreateLocalUserAccess do
  use Ecto.Migration

  @tenant_tables ~w(
    platform_identity_users
    platform_identity_password_credentials
    platform_identity_sessions
    platform_identity_login_throttles
  )

  def up do
    create_users()
    create_credentials()
    create_sessions()
    create_login_throttles()
    create_tenant_foreign_keys()
    enable_tenant_isolation()
  end

  def down do
    Enum.each(Enum.reverse(@tenant_tables), &disable_tenant_isolation/1)
    drop table(:platform_identity_login_throttles)
    drop table(:platform_identity_sessions)
    drop table(:platform_identity_password_credentials)
    drop table(:platform_identity_users)
  end

  defp create_users do
    create table(:platform_identity_users, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :username, :string, null: false, size: 64
      add :normalized_username, :string, null: false, size: 64
      add :display_name, :string, null: false, size: 120
      add :access_profile, :string, null: false, size: 48
      add :status, :string, null: false, size: 32, default: "pending_activation"
      add :must_change_password, :boolean, null: false, default: true
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:platform_identity_users, [:tenant_id, :normalized_username],
             name: :platform_identity_users_tenant_username_index
           )

    create unique_index(:platform_identity_users, [:tenant_id, :id],
             name: :platform_identity_users_tenant_identity_index
           )

    create constraint(:platform_identity_users, :platform_identity_users_username_check,
             check: "normalized_username ~ '^[a-z0-9][a-z0-9._-]{2,63}$'"
           )

    create constraint(:platform_identity_users, :platform_identity_users_profile_check,
             check:
               "access_profile IN ('entity_onboarding_operator', 'entity_onboarding_reviewer')"
           )

    create constraint(:platform_identity_users, :platform_identity_users_status_check,
             check: "status IN ('pending_activation', 'active', 'suspended')"
           )

    create constraint(:platform_identity_users, :platform_identity_users_version_check,
             check: "lock_version > 0"
           )
  end

  defp create_credentials do
    create table(:platform_identity_password_credentials, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :actor_id, :uuid, null: false
      add :password_hash, :string, null: false, size: 512
      add :generation, :integer, null: false, default: 1
      add :changed_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:platform_identity_password_credentials, [:tenant_id, :actor_id],
             name: :platform_identity_credentials_tenant_actor_index
           )

    create constraint(
             :platform_identity_password_credentials,
             :platform_identity_credentials_generation_check,
             check: "generation > 0"
           )
  end

  defp create_sessions do
    create table(:platform_identity_sessions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :actor_id, :uuid, null: false
      add :token_hash, :binary, null: false
      add :credential_generation, :integer, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :revoked_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:platform_identity_sessions, [:tenant_id, :token_hash],
             name: :platform_identity_sessions_tenant_token_index
           )

    create index(:platform_identity_sessions, [:tenant_id, :actor_id, :expires_at],
             name: :platform_identity_sessions_actor_expiry_index
           )

    create constraint(:platform_identity_sessions, :platform_identity_sessions_token_hash_check,
             check: "octet_length(token_hash) = 32"
           )

    create constraint(
             :platform_identity_sessions,
             :platform_identity_sessions_generation_check,
             check: "credential_generation > 0"
           )
  end

  defp create_login_throttles do
    create table(:platform_identity_login_throttles, primary_key: false) do
      add :tenant_id, :uuid, primary_key: true
      add :identifier_hash, :binary, primary_key: true
      add :failed_count, :integer, null: false, default: 0
      add :window_started_at, :utc_datetime_usec, null: false
      add :blocked_until, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(
             :platform_identity_login_throttles,
             :platform_identity_login_throttles_hash_check,
             check: "octet_length(identifier_hash) = 32"
           )

    create constraint(
             :platform_identity_login_throttles,
             :platform_identity_login_throttles_count_check,
             check: "failed_count >= 0 AND failed_count <= 1000"
           )
  end

  defp create_tenant_foreign_keys do
    Enum.each(~w(platform_identity_password_credentials platform_identity_sessions), fn table ->
      execute("""
      ALTER TABLE #{table}
      ADD CONSTRAINT #{table}_tenant_actor_fkey
      FOREIGN KEY (tenant_id, actor_id)
      REFERENCES platform_identity_users (tenant_id, id)
      ON DELETE RESTRICT
      """)
    end)
  end

  defp enable_tenant_isolation do
    Enum.each(@tenant_tables, fn table ->
      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")

      execute("""
      CREATE POLICY #{table}_tenant_isolation ON #{table}
      USING (tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid)
      WITH CHECK (tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid)
      """)
    end)
  end

  defp disable_tenant_isolation(table) do
    execute("DROP POLICY IF EXISTS #{table}_tenant_isolation ON #{table}")
    execute("ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY")
    execute("ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY")
  end
end
