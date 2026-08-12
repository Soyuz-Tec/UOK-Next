defmodule UokNext.Modules.Platform.Workflow.Infrastructure.HumanTaskRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "platform_workflow_human_tasks" do
    field :tenant_id, :binary_id
    field :task_kind, :string
    field :subject_type, :string
    field :subject_id, :binary_id
    field :subject_version, :integer
    field :required_permission, :string
    field :status, :string, default: "open"
    field :opened_by_actor_id, :binary_id
    field :opened_reason, :string
    field :resolution, :string
    field :completion_reason, :string
    field :completed_by_actor_id, :binary_id
    field :completed_at, :utc_datetime_usec
    field :lock_version, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @create_fields ~w(
    tenant_id task_kind subject_type subject_id subject_version required_permission
    opened_by_actor_id opened_reason
  )a

  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(record, attrs) do
    record
    |> cast(attrs, @create_fields)
    |> validate_required(@create_fields)
    |> unique_constraint([:tenant_id, :task_kind, :subject_type, :subject_id],
      name: :platform_workflow_human_tasks_one_open_subject_index
    )
    |> database_constraints()
  end

  @spec completion_changeset(t(), map()) :: Ecto.Changeset.t()
  def completion_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :status,
      :resolution,
      :completion_reason,
      :completed_by_actor_id,
      :completed_at
    ])
    |> validate_required([
      :status,
      :resolution,
      :completion_reason,
      :completed_by_actor_id,
      :completed_at
    ])
    |> optimistic_lock(:lock_version)
    |> database_constraints()
  end

  defp database_constraints(changeset) do
    changeset
    |> check_constraint(:task_kind, name: :platform_workflow_human_tasks_kind_check)
    |> check_constraint(:subject_type, name: :platform_workflow_human_tasks_subject_type_check)
    |> check_constraint(:required_permission,
      name: :platform_workflow_human_tasks_permission_check
    )
    |> check_constraint(:status, name: :platform_workflow_human_tasks_status_check)
    |> check_constraint(:resolution, name: :platform_workflow_human_tasks_resolution_check)
    |> check_constraint(:lock_version, name: :platform_workflow_human_tasks_version_check)
    |> check_constraint(:completed_at, name: :platform_workflow_human_tasks_completion_check)
  end
end
