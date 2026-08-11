defmodule UokNext.Kernel.CommandContext do
  @moduledoc """
  Authenticated execution context supplied to every consequential command.

  Constructing this value validates shape only. Authentication and permission
  issuance remain the responsibility of the identity boundary.
  """

  alias UokNext.Kernel.CommandError

  @enforce_keys [:tenant_id, :actor_id, :correlation_id, :permissions]
  defstruct [:tenant_id, :actor_id, :correlation_id, :permissions]

  @type t :: %__MODULE__{
          tenant_id: Ecto.UUID.t(),
          actor_id: Ecto.UUID.t(),
          correlation_id: Ecto.UUID.t(),
          permissions: MapSet.t(String.t())
        }

  @spec new(map()) :: {:ok, t()} | {:error, CommandError.t()}
  def new(attrs) when is_map(attrs) do
    with {:ok, tenant_id} <- uuid(attrs, :tenant_id),
         {:ok, actor_id} <- uuid(attrs, :actor_id),
         {:ok, correlation_id} <- uuid(attrs, :correlation_id),
         {:ok, permissions} <- permissions(attrs) do
      {:ok,
       %__MODULE__{
         tenant_id: tenant_id,
         actor_id: actor_id,
         correlation_id: correlation_id,
         permissions: permissions
       }}
    end
  end

  def new(_attrs), do: invalid("command context must be an object")

  @spec permitted?(t(), String.t()) :: boolean()
  def permitted?(%__MODULE__{permissions: permissions}, permission) do
    MapSet.member?(permissions, permission)
  end

  defp uuid(attrs, key) do
    value = Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> invalid("#{key} must be a UUID")
    end
  end

  defp permissions(attrs) do
    value = Map.get(attrs, :permissions) || Map.get(attrs, "permissions")

    if valid_permissions?(value) do
      {:ok, MapSet.new(value)}
    else
      invalid("permissions must be a bounded list of permission names")
    end
  end

  defp valid_permissions?(permissions) when is_list(permissions) and length(permissions) <= 64 do
    Enum.all?(permissions, fn permission ->
      is_binary(permission) and byte_size(permission) in 1..80 and
        String.match?(permission, ~r/^[a-z][a-z0-9_.:-]*$/)
    end)
  end

  defp valid_permissions?(_permissions), do: false

  defp invalid(message) do
    {:error, CommandError.new("invalid_context", message, 401)}
  end
end
