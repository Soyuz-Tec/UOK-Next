defmodule UokNext.Repo.Migrations.CreateDurableOutboxHandoff do
  use Ecto.Migration

  @outbox_table "kernel_outbox_events"
  @job_table "kernel_durable_jobs"
  @delivery_table "kernel_outbox_deliveries"

  def up do
    create unique_index(@outbox_table, [:tenant_id, :id],
             name: :kernel_outbox_events_tenant_identity_index
           )

    create table(@job_table, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :job_kind, :string, null: false, size: 80
      add :outbox_event_id, :uuid, null: false
      add :status, :string, null: false, size: 24
      add :run_at, :utc_datetime_usec, null: false
      add :attempt_count, :integer, null: false, default: 0
      add :max_attempts, :integer, null: false
      add :lease_token, :uuid
      add :lease_expires_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :last_error_code, :string, size: 64
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(@job_table, [:tenant_id, :outbox_event_id],
             name: :kernel_durable_jobs_event_index
           )

    create index(@job_table, [:status, :run_at],
             name: :kernel_durable_jobs_due_index,
             where: "status = 'scheduled'"
           )

    create index(@job_table, [:status, :lease_expires_at],
             name: :kernel_durable_jobs_lease_index,
             where: "status = 'running'"
           )

    create constraint(@job_table, :kernel_durable_jobs_kind_check,
             check: "job_kind = 'kernel.outbox.publish'"
           )

    create constraint(@job_table, :kernel_durable_jobs_status_check,
             check: "status IN ('scheduled', 'running', 'completed', 'dead_letter')"
           )

    create constraint(@job_table, :kernel_durable_jobs_attempt_check,
             check: "max_attempts BETWEEN 1 AND 10 AND attempt_count BETWEEN 0 AND max_attempts"
           )

    create constraint(@job_table, :kernel_durable_jobs_lease_shape_check,
             check: """
             (status = 'running' AND lease_token IS NOT NULL AND lease_expires_at IS NOT NULL AND
              completed_at IS NULL) OR
             (status = 'completed' AND lease_token IS NULL AND lease_expires_at IS NULL AND
              completed_at IS NOT NULL) OR
             (status IN ('scheduled', 'dead_letter') AND lease_token IS NULL AND
              lease_expires_at IS NULL AND completed_at IS NULL)
             """
           )

    create constraint(@job_table, :kernel_durable_jobs_error_code_check,
             check: "last_error_code IS NULL OR last_error_code ~ '^[a-z][a-z0-9_]{2,63}$'"
           )

    execute """
    ALTER TABLE #{@job_table}
    ADD CONSTRAINT kernel_durable_jobs_tenant_outbox_fkey
    FOREIGN KEY (tenant_id, outbox_event_id)
    REFERENCES #{@outbox_table} (tenant_id, id)
    ON DELETE RESTRICT
    NOT VALID
    """

    execute """
    ALTER TABLE #{@job_table}
    VALIDATE CONSTRAINT kernel_durable_jobs_tenant_outbox_fkey
    """

    create table(@delivery_table, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :outbox_event_id, :uuid, null: false
      add :consumer, :string, null: false, size: 80
      add :event_digest, :binary, null: false
      add :delivered_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(@delivery_table, [:tenant_id, :outbox_event_id, :consumer],
             name: :kernel_outbox_deliveries_event_consumer_index
           )

    create constraint(@delivery_table, :kernel_outbox_deliveries_consumer_check,
             check: "consumer = 'kernel.local_handoff.v1'"
           )

    create constraint(@delivery_table, :kernel_outbox_deliveries_digest_check,
             check: "octet_length(event_digest) = 32"
           )

    execute """
    ALTER TABLE #{@delivery_table}
    ADD CONSTRAINT kernel_outbox_deliveries_tenant_outbox_fkey
    FOREIGN KEY (tenant_id, outbox_event_id)
    REFERENCES #{@outbox_table} (tenant_id, id)
    ON DELETE RESTRICT
    NOT VALID
    """

    execute """
    ALTER TABLE #{@delivery_table}
    VALIDATE CONSTRAINT kernel_outbox_deliveries_tenant_outbox_fkey
    """

    replace_outbox_policy()
    enable_worker_rls(@job_table)
    enable_worker_rls(@delivery_table)
  end

  def down do
    execute("DROP POLICY IF EXISTS #{@delivery_table}_worker_access ON #{@delivery_table}")
    execute("ALTER TABLE #{@delivery_table} NO FORCE ROW LEVEL SECURITY")
    execute("ALTER TABLE #{@delivery_table} DISABLE ROW LEVEL SECURITY")
    execute("DROP POLICY IF EXISTS #{@job_table}_worker_access ON #{@job_table}")
    execute("ALTER TABLE #{@job_table} NO FORCE ROW LEVEL SECURITY")
    execute("ALTER TABLE #{@job_table} DISABLE ROW LEVEL SECURITY")
    restore_tenant_outbox_policy()
    drop table(@delivery_table)
    drop table(@job_table)

    drop index(@outbox_table, [:tenant_id, :id],
           name: :kernel_outbox_events_tenant_identity_index
         )
  end

  defp replace_outbox_policy do
    execute("DROP POLICY kernel_outbox_events_tenant_isolation ON #{@outbox_table}")

    execute """
    CREATE POLICY kernel_outbox_events_tenant_isolation ON #{@outbox_table}
    USING (
      current_user = 'uok_outbox' OR
      tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid
    )
    WITH CHECK (
      current_user = 'uok_outbox' OR
      tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid
    )
    """
  end

  defp restore_tenant_outbox_policy do
    execute("DROP POLICY kernel_outbox_events_tenant_isolation ON #{@outbox_table}")

    execute """
    CREATE POLICY kernel_outbox_events_tenant_isolation ON #{@outbox_table}
    USING (
      tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid
    )
    WITH CHECK (
      tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid
    )
    """
  end

  defp enable_worker_rls(table) do
    execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")

    execute """
    CREATE POLICY #{table}_worker_access ON #{table}
    USING (
      current_user = 'uok_outbox' OR
      tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid
    )
    WITH CHECK (
      current_user = 'uok_outbox' OR
      tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid
    )
    """
  end
end
