defmodule UokNext.Modules.Master.Parties.Infrastructure.PartyRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "master_parties" do
    field :tenant_id, :binary_id
    field :stable_identifier, :string
    field :legal_name, :string
    field :country_code, :string
    field :party_kind, :string
    field :status, :string, default: "draft"
    field :evidence_metadata, :map
    field :evidence_submitted_at, :utc_datetime_usec
    field :decision_reason, :string
    field :decision_actor_id, :binary_id
    field :decided_at, :utc_datetime_usec
    field :lock_version, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [:tenant_id, :stable_identifier, :legal_name, :country_code, :party_kind])
    |> validate_required([
      :tenant_id,
      :stable_identifier,
      :legal_name,
      :country_code,
      :party_kind
    ])
    |> unique_constraint([:tenant_id, :stable_identifier],
      name: :master_parties_tenant_stable_identifier_index
    )
    |> database_constraints()
  end

  @spec transition_changeset(t(), map()) :: Ecto.Changeset.t()
  def transition_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :status,
      :evidence_metadata,
      :evidence_submitted_at,
      :decision_reason,
      :decision_actor_id,
      :decided_at
    ])
    |> optimistic_lock(:lock_version)
    |> database_constraints()
  end

  defp database_constraints(changeset) do
    changeset
    |> check_constraint(:country_code, name: :master_parties_country_code_check)
    |> check_constraint(:party_kind, name: :master_parties_kind_check)
    |> check_constraint(:status, name: :master_parties_status_check)
    |> check_constraint(:lock_version, name: :master_parties_lock_version_check)
  end
end
