defmodule UokNext.Repo.Migrations.CreateGovernedHumanTasks do
  use Ecto.Migration

  def up do
    create table(:platform_workflow_human_tasks, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :task_kind, :string, null: false, size: 120
      add :subject_type, :string, null: false, size: 120
      add :subject_id, :uuid, null: false
      add :subject_version, :integer, null: false
      add :required_permission, :string, null: false, size: 120
      add :status, :string, null: false, size: 24, default: "open"
      add :opened_by_actor_id, :uuid, null: false
      add :opened_reason, :string, null: false, size: 500
      add :resolution, :string, size: 32
      add :completion_reason, :string, size: 500
      add :completed_by_actor_id, :uuid
      add :completed_at, :utc_datetime_usec
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:platform_workflow_human_tasks, [:tenant_id, :id],
             name: :platform_workflow_human_tasks_tenant_identity_index
           )

    create unique_index(
             :platform_workflow_human_tasks,
             [:tenant_id, :task_kind, :subject_type, :subject_id],
             where: "status = 'open'",
             name: :platform_workflow_human_tasks_one_open_subject_index
           )

    create index(:platform_workflow_human_tasks, [:tenant_id, :status, :inserted_at],
             name: :platform_workflow_human_tasks_queue_index
           )

    create constraint(:platform_workflow_human_tasks, :platform_workflow_human_tasks_kind_check,
             check: "task_kind ~ '^[a-z][a-z0-9_.:-]{2,119}$'"
           )

    create constraint(
             :platform_workflow_human_tasks,
             :platform_workflow_human_tasks_subject_type_check,
             check: "subject_type ~ '^[a-z][a-z0-9_.:-]{1,119}$'"
           )

    create constraint(
             :platform_workflow_human_tasks,
             :platform_workflow_human_tasks_permission_check,
             check: "required_permission ~ '^[a-z][a-z0-9_.:-]{2,119}$'"
           )

    create constraint(:platform_workflow_human_tasks, :platform_workflow_human_tasks_status_check,
             check: "status IN ('open', 'completed')"
           )

    create constraint(
             :platform_workflow_human_tasks,
             :platform_workflow_human_tasks_resolution_check,
             check: "resolution IS NULL OR resolution IN ('approve', 'hold')"
           )

    create constraint(
             :platform_workflow_human_tasks,
             :platform_workflow_human_tasks_version_check,
             check: "subject_version > 0 AND lock_version > 0"
           )

    create constraint(
             :platform_workflow_human_tasks,
             :platform_workflow_human_tasks_completion_check,
             check: """
             (status = 'open' AND resolution IS NULL AND completion_reason IS NULL AND
              completed_by_actor_id IS NULL AND completed_at IS NULL) OR
             (status = 'completed' AND resolution IS NOT NULL AND
              completion_reason IS NOT NULL AND completed_by_actor_id IS NOT NULL AND
              completed_at IS NOT NULL)
             """
           )

    execute "ALTER TABLE platform_workflow_human_tasks ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE platform_workflow_human_tasks FORCE ROW LEVEL SECURITY"

    execute """
    CREATE POLICY platform_workflow_human_tasks_tenant_isolation
    ON platform_workflow_human_tasks
    USING (
      tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid
    )
    WITH CHECK (
      tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid
    )
    """
  end

  def down do
    execute "DROP POLICY IF EXISTS platform_workflow_human_tasks_tenant_isolation ON platform_workflow_human_tasks"
    drop table(:platform_workflow_human_tasks)
  end
end
