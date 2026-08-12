defmodule UokNext.Modules.Platform.Identity.Infrastructure.SignedAccessToken do
  @moduledoc false

  alias UokNext.Kernel.CommandError

  @salt "uok-next-local-qualification-access-v1"
  @max_age_seconds 28_800

  @spec authenticate_local(String.t()) :: {:ok, map()} | {:error, CommandError.t()}
  def authenticate_local(access_code) when is_binary(access_code) do
    with {:ok, identity} <- configured_identity(),
         true <- secure_match?(access_code, identity.access_code) do
      claims = claims(identity)
      token = Phoenix.Token.sign(UokNextWeb.Endpoint, @salt, claims)

      {:ok,
       %{
         "access_token" => token,
         "token_type" => "Bearer",
         "expires_in" => @max_age_seconds,
         "identity" => public_identity(identity)
       }}
    else
      _failure -> unauthorized()
    end
  end

  def authenticate_local(_access_code), do: unauthorized()

  @spec verify(String.t()) :: {:ok, map()} | {:error, CommandError.t()}
  def verify(token) when is_binary(token) and byte_size(token) in 32..2_048 do
    with {:ok, identity} <- configured_identity(),
         {:ok, claims} <-
           Phoenix.Token.verify(UokNextWeb.Endpoint, @salt, token, max_age: @max_age_seconds),
         true <- claims == claims(identity) do
      {:ok, public_identity(identity)}
    else
      _failure -> unauthorized()
    end
  end

  def verify(_token), do: unauthorized()

  defp configured_identity do
    case Application.get_env(:uok_next, :local_qualification_identity) do
      identity when is_map(identity) -> validate_identity(identity)
      _missing -> :error
    end
  end

  defp validate_identity(identity) do
    with :local_qualification <- Application.get_env(:uok_next, :deployment_profile),
         {:ok, tenant_id} <- Ecto.UUID.cast(Map.get(identity, :tenant_id)),
         {:ok, actor_id} <- Ecto.UUID.cast(Map.get(identity, :actor_id)),
         access_code when is_binary(access_code) and byte_size(access_code) in 32..128 <-
           Map.get(identity, :access_code),
         permissions when is_list(permissions) and length(permissions) in 1..64 <-
           Map.get(identity, :permissions) do
      {:ok,
       %{
         tenant_id: tenant_id,
         actor_id: actor_id,
         access_code: access_code,
         permissions: permissions
       }}
    else
      _invalid -> :error
    end
  end

  defp claims(identity) do
    %{
      version: 1,
      tenant_id: identity.tenant_id,
      actor_id: identity.actor_id,
      permissions: Enum.sort(identity.permissions)
    }
  end

  defp public_identity(identity) do
    %{
      "tenant_id" => identity.tenant_id,
      "actor_id" => identity.actor_id,
      "permissions" => Enum.sort(identity.permissions)
    }
  end

  defp secure_match?(left, right) when byte_size(left) == byte_size(right),
    do: Plug.Crypto.secure_compare(left, right)

  defp secure_match?(_left, _right), do: false

  defp unauthorized,
    do: {:error, CommandError.new("unauthorized", "authentication failed", 401)}
end
