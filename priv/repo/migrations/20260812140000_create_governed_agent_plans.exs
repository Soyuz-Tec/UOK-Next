defmodule UokNext.Repo.Migrations.CreateGovernedAgentPlans do
  use Ecto.Migration

  def up do
    create table(:platform_agents_plans, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :runbook_key, :string, null: false, size: 120
      add :runbook_version, :integer, null: false
      add :subject_type, :string, null: false, size: 120
      add :subject_id, :uuid, null: false
      add :subject_version, :integer, null: false
      add :step_graph, :map, null: false
      add :evidence_ids, {:array, :uuid}, null: false, default: []
      add :plan_sha256, :string, null: false, size: 64
      add :status, :string, null: false, size: 24, default: "proposed"
      add :review_task_id, :uuid, null: false
      add :proposed_by_actor_id, :uuid, null: false
      add :proposal_reason, :string, null: false, size: 500
      add :proposed_at, :utc_datetime_usec, null: false
      add :decided_by_actor_id, :uuid
      add :decision_reason, :string, size: 500
      add :decided_at, :utc_datetime_usec
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:platform_agents_plans, [:tenant_id, :id],
             name: :platform_agents_plans_tenant_identity_index
           )

    create unique_index(:platform_agents_plans, [:tenant_id, :plan_sha256],
             name: :platform_agents_plans_tenant_digest_index
           )

    create index(:platform_agents_plans, [:tenant_id, :status, :inserted_at],
             name: :platform_agents_plans_review_queue_index
           )

    create constraint(:platform_agents_plans, :platform_agents_plans_identifier_check,
             check: """
             runbook_key ~ '^[a-z][a-z0-9_.:-]{2,119}$' AND
             subject_type ~ '^[a-z][a-z0-9_.:-]{1,119}$'
             """
           )

    create constraint(:platform_agents_plans, :platform_agents_plans_digest_check,
             check: "plan_sha256 ~ '^[0-9a-f]{64}$'"
           )

    create constraint(:platform_agents_plans, :platform_agents_plans_version_check,
             check: "runbook_version > 0 AND subject_version > 0 AND lock_version > 0"
           )

    create constraint(:platform_agents_plans, :platform_agents_plans_graph_check,
             check: """
             jsonb_typeof(step_graph) = 'object' AND
             jsonb_typeof(step_graph -> 'items') = 'array' AND
             jsonb_array_length(step_graph -> 'items') BETWEEN 1 AND 32 AND
             cardinality(evidence_ids) BETWEEN 0 AND 16
             """
           )

    create constraint(:platform_agents_plans, :platform_agents_plans_lifecycle_check,
             check: """
             (status = 'proposed' AND decided_by_actor_id IS NULL AND
              decision_reason IS NULL AND decided_at IS NULL) OR
             (status IN ('approved', 'hold') AND decided_by_actor_id IS NOT NULL AND
              decision_reason IS NOT NULL AND decided_at IS NOT NULL)
             """
           )

    execute "ALTER TABLE platform_agents_plans ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE platform_agents_plans FORCE ROW LEVEL SECURITY"

    execute """
    CREATE POLICY platform_agents_plans_tenant_isolation
    ON platform_agents_plans
    USING (tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid)
    WITH CHECK (tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid)
    """
  end

  def down do
    execute "DROP POLICY IF EXISTS platform_agents_plans_tenant_isolation ON platform_agents_plans"
    drop table(:platform_agents_plans)
  end
end
