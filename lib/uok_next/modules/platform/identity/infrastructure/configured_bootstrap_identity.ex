defmodule UokNext.Modules.Platform.Identity.Infrastructure.ConfiguredBootstrapIdentity do
  @moduledoc false

  @behaviour UokNext.Modules.Platform.Identity.Application.BootstrapIdentityPort

  @permission_pattern ~r/\A[a-z][a-z0-9_-]*(?::[a-z][a-z0-9_-]*)+\z/

  @impl true
  def authenticate(access_code) do
    with {:ok, identity, configured_code} <- configured_with_secret(),
         true <- secure_match?(access_code, configured_code) do
      {:ok, identity}
    else
      _failure -> :error
    end
  end

  @impl true
  def current do
    with {:ok, identity, _configured_code} <- configured_with_secret(), do: {:ok, identity}
  end

  defp configured_with_secret do
    case Application.get_env(:uok_next, :local_qualification_identity) do
      identity when is_map(identity) -> validate(identity)
      _missing -> :error
    end
  end

  defp validate(identity) do
    with :local_qualification <- Application.get_env(:uok_next, :deployment_profile),
         {:ok, tenant_id} <- Ecto.UUID.cast(Map.get(identity, :tenant_id)),
         {:ok, actor_id} <- Ecto.UUID.cast(Map.get(identity, :actor_id)),
         access_code when is_binary(access_code) and byte_size(access_code) in 32..128 <-
           Map.get(identity, :access_code),
         permissions when is_list(permissions) and length(permissions) in 1..64 <-
           Map.get(identity, :permissions),
         true <- valid_permissions?(permissions) do
      {:ok, %{tenant_id: tenant_id, actor_id: actor_id, permissions: Enum.uniq(permissions)},
       access_code}
    else
      _invalid -> :error
    end
  end

  defp valid_permissions?(permissions) do
    Enum.all?(permissions, fn permission ->
      is_binary(permission) and byte_size(permission) in 3..96 and
        Regex.match?(@permission_pattern, permission)
    end)
  end

  defp secure_match?(presented, configured) do
    candidate =
      if is_binary(presented) and byte_size(presented) in 32..128,
        do: presented,
        else: "invalid-local-bootstrap-code"

    candidate_hash = :crypto.hash(:sha256, ["bootstrap-code", 0, candidate])
    configured_hash = :crypto.hash(:sha256, ["bootstrap-code", 0, configured])
    Plug.Crypto.secure_compare(candidate_hash, configured_hash)
  end
end
