defmodule UokNext.Repo.Migrations.EnableTenantRowLevelSecurity do
  use Ecto.Migration

  @tenant_tables ~w(
    kernel_command_receipts
    kernel_audit_events
    kernel_outbox_events
    master_parties
  )

  def up do
    Enum.each(@tenant_tables, fn table ->
      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")

      execute("""
      CREATE POLICY #{table}_tenant_isolation ON #{table}
      USING (
        tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid
      )
      WITH CHECK (
        tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid
      )
      """)
    end)
  end

  def down do
    Enum.each(Enum.reverse(@tenant_tables), fn table ->
      execute("DROP POLICY IF EXISTS #{table}_tenant_isolation ON #{table}")
      execute("ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY")
    end)
  end
end
