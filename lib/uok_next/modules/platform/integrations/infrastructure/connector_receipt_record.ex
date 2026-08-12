defmodule UokNext.Modules.Platform.Integrations.Infrastructure.ConnectorReceiptRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "platform_integrations_connector_receipts" do
    field :tenant_id, :binary_id
    field :connector_role, :string
    field :operation, :string
    field :delivery_key, :string
    field :attempt_number, :integer
    field :request_sha256, :string
    field :subject_type, :string
    field :subject_id, :binary_id
    field :subject_version, :integer
    field :status, :string, default: "attempted"
    field :timeout_ms, :integer
    field :deadline_at, :utc_datetime_usec
    field :previous_receipt_id, :binary_id
    field :response_sha256, :string
    field :external_reference, :string
    field :retry_after_seconds, :integer
    field :outcome_reason, :string
    field :attempted_by_actor_id, :binary_id
    field :attempted_at, :utc_datetime_usec
    field :reconciled_by_actor_id, :binary_id
    field :reconciled_at, :utc_datetime_usec
    field :lock_version, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @create_fields ~w(
    tenant_id connector_role operation delivery_key attempt_number request_sha256
    subject_type subject_id subject_version timeout_ms deadline_at previous_receipt_id
    attempted_by_actor_id attempted_at
  )a

  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(record, attrs) do
    record
    |> cast(attrs, @create_fields)
    |> validate_required(@create_fields -- [:previous_receipt_id])
    |> unique_constraint([:tenant_id, :connector_role, :delivery_key, :attempt_number],
      name: :platform_integrations_connector_receipts_delivery_attempt_index
    )
    |> database_constraints()
  end

  @spec reconciliation_changeset(t(), map()) :: Ecto.Changeset.t()
  def reconciliation_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :status,
      :response_sha256,
      :external_reference,
      :retry_after_seconds,
      :outcome_reason,
      :reconciled_by_actor_id,
      :reconciled_at
    ])
    |> validate_required([:status, :outcome_reason, :reconciled_by_actor_id, :reconciled_at])
    |> optimistic_lock(:lock_version)
    |> database_constraints()
  end

  defp database_constraints(changeset) do
    changeset
    |> check_constraint(:connector_role,
      name: :platform_integrations_connector_receipts_identifier_check
    )
    |> check_constraint(:request_sha256,
      name: :platform_integrations_connector_receipts_digest_check
    )
    |> check_constraint(:subject_version,
      name: :platform_integrations_connector_receipts_version_check
    )
    |> check_constraint(:attempt_number,
      name: :platform_integrations_connector_receipts_retry_lineage_check
    )
    |> check_constraint(:status,
      name: :platform_integrations_connector_receipts_lifecycle_check
    )
    |> foreign_key_constraint(:previous_receipt_id,
      name: :platform_integrations_connector_receipts_previous_fkey
    )
  end
end
