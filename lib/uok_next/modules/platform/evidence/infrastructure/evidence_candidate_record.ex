defmodule UokNext.Modules.Platform.Evidence.Infrastructure.EvidenceCandidateRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "platform_evidence_objects" do
    field :tenant_id, :binary_id
    field :subject_type, :string
    field :subject_id, :binary_id
    field :content_type, :string
    field :byte_size, :integer
    field :sha256, :string
    field :object_key, :string
    field :classification, :string
    field :state, :string, default: "pending_upload"
    field :storage_receipt, :map
    field :verified_at, :utc_datetime_usec
    field :lock_version, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :id,
      :tenant_id,
      :subject_type,
      :subject_id,
      :content_type,
      :byte_size,
      :sha256,
      :object_key,
      :classification
    ])
    |> validate_required([
      :id,
      :tenant_id,
      :subject_type,
      :subject_id,
      :content_type,
      :byte_size,
      :sha256,
      :object_key,
      :classification
    ])
    |> unique_constraint(:id, name: :platform_evidence_objects_pkey)
    |> unique_constraint(:object_key, name: :platform_evidence_objects_object_key_index)
    |> database_constraints()
  end

  @spec verification_changeset(t(), map()) :: Ecto.Changeset.t()
  def verification_changeset(record, attrs) do
    record
    |> cast(attrs, [:state, :storage_receipt, :verified_at])
    |> optimistic_lock(:lock_version)
    |> database_constraints()
  end

  defp database_constraints(changeset) do
    changeset
    |> check_constraint(:subject_type, name: :platform_evidence_objects_subject_type_check)
    |> check_constraint(:content_type, name: :platform_evidence_objects_content_type_check)
    |> check_constraint(:byte_size, name: :platform_evidence_objects_size_check)
    |> check_constraint(:sha256, name: :platform_evidence_objects_sha256_check)
    |> check_constraint(:classification, name: :platform_evidence_objects_classification_check)
    |> check_constraint(:state, name: :platform_evidence_objects_state_check)
    |> check_constraint(:state, name: :platform_evidence_objects_lifecycle_check)
    |> check_constraint(:lock_version, name: :platform_evidence_objects_version_check)
  end
end
