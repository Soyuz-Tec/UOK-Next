defmodule UokNext.Modules.Platform.Integrations.Infrastructure.CommunicationLinkRecord do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "platform_integrations_communication_links" do
    field :tenant_id, :binary_id
    field :subject_type, :string
    field :subject_id, :binary_id
    field :subject_version, :integer
    field :conversation_id, :binary_id
    field :created_by_actor_id, :binary_id
    field :lock_version, :integer, default: 1
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(record, attrs) do
    record
    |> cast(
      attrs,
      ~w(id tenant_id subject_type subject_id subject_version conversation_id created_by_actor_id)a
    )
    |> validate_required(
      ~w(id tenant_id subject_type subject_id subject_version conversation_id created_by_actor_id)a
    )
    |> unique_constraint(:conversation_id,
      name: :platform_integrations_communication_links_binding_index
    )
    |> foreign_key_constraint(:subject_id,
      name: :platform_integrations_communication_links_party_fkey
    )
    |> check_constraint(:subject_type,
      name: :platform_integrations_communication_links_shape_check
    )
  end

  @type t :: %__MODULE__{}
end
