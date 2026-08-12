defmodule UokNext.Modules.Platform.Agents.Infrastructure.AgentPlanRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "platform_agents_plans" do
    field :tenant_id, :binary_id
    field :runbook_key, :string
    field :runbook_version, :integer
    field :subject_type, :string
    field :subject_id, :binary_id
    field :subject_version, :integer
    field :step_graph, :map
    field :evidence_ids, {:array, :binary_id}, default: []
    field :plan_sha256, :string
    field :status, :string, default: "proposed"
    field :review_task_id, :binary_id
    field :proposed_by_actor_id, :binary_id
    field :proposal_reason, :string
    field :proposed_at, :utc_datetime_usec
    field :decided_by_actor_id, :binary_id
    field :decision_reason, :string
    field :decided_at, :utc_datetime_usec
    field :lock_version, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @create_fields ~w(
    id tenant_id runbook_key runbook_version subject_type subject_id subject_version
    step_graph evidence_ids plan_sha256 review_task_id proposed_by_actor_id proposal_reason
    proposed_at
  )a

  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(record, attrs) do
    record
    |> cast(attrs, @create_fields)
    |> validate_required(@create_fields)
    |> unique_constraint([:tenant_id, :plan_sha256],
      name: :platform_agents_plans_tenant_digest_index
    )
    |> database_constraints()
  end

  @spec decision_changeset(t(), map()) :: Ecto.Changeset.t()
  def decision_changeset(record, attrs) do
    record
    |> cast(attrs, [:status, :decided_by_actor_id, :decision_reason, :decided_at])
    |> validate_required([:status, :decided_by_actor_id, :decision_reason, :decided_at])
    |> optimistic_lock(:lock_version)
    |> database_constraints()
  end

  defp database_constraints(changeset) do
    changeset
    |> check_constraint(:runbook_key, name: :platform_agents_plans_identifier_check)
    |> check_constraint(:plan_sha256, name: :platform_agents_plans_digest_check)
    |> check_constraint(:runbook_version, name: :platform_agents_plans_version_check)
    |> check_constraint(:step_graph, name: :platform_agents_plans_graph_check)
    |> check_constraint(:status, name: :platform_agents_plans_lifecycle_check)
  end
end
