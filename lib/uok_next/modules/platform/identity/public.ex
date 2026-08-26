defmodule UokNext.Modules.Platform.Identity.Public do
  @moduledoc """
  Supported identity boundary for the isolated local qualification profile.

  A production identity adapter is intentionally not selected by this module.
  """

  alias UokNext.Kernel.CommandError

  alias UokNext.Modules.Platform.Identity.Application.{
    BootstrapSessions,
    PasswordSessions,
    UserAccess
  }

  alias UokNext.Modules.Platform.Identity.Infrastructure.{
    BootstrapSessionToken,
    ConfiguredBootstrapIdentity,
    EctoIdentityStore,
    PasswordHasher,
    SessionToken
  }

  @services %{
    store: EctoIdentityStore,
    passwords: PasswordHasher,
    tokens: SessionToken
  }

  @bootstrap_services %{
    store: EctoIdentityStore,
    bootstrap_identity: ConfiguredBootstrapIdentity,
    bootstrap_tokens: BootstrapSessionToken
  }

  @spec authenticate_local(String.t()) :: tuple()
  def authenticate_local(access_code),
    do: BootstrapSessions.authenticate(@bootstrap_services, access_code)

  @spec authenticate_password(map()) :: tuple()
  def authenticate_password(attrs), do: PasswordSessions.authenticate(@services, attrs)

  @spec verify_access_token(String.t()) :: tuple()
  def verify_access_token("uokls1." <> _rest = token),
    do: PasswordSessions.verify(@services, token)

  def verify_access_token("uokba1." <> _rest = token),
    do: BootstrapSessions.verify(@bootstrap_services, token)

  def verify_access_token(_token), do: unauthorized()

  @spec revoke_access_token(String.t(), UokNext.Kernel.CommandContext.t()) :: tuple()
  def revoke_access_token("uokls1." <> _rest = token, context),
    do: PasswordSessions.revoke(@services, token, context)

  def revoke_access_token("uokba1." <> _rest = token, context),
    do: BootstrapSessions.revoke(@bootstrap_services, token, context)

  def revoke_access_token(_token, _context), do: unauthorized()

  @spec change_password(map(), UokNext.Kernel.CommandContext.t(), String.t()) :: tuple()
  def change_password(attrs, context, idempotency_key),
    do: PasswordSessions.change_password(@services, attrs, context, idempotency_key)

  @spec create_local_user(map(), UokNext.Kernel.CommandContext.t(), String.t()) :: tuple()
  def create_local_user(attrs, context, idempotency_key),
    do: UserAccess.create(@services, attrs, context, idempotency_key)

  @spec list_local_users(pos_integer(), UokNext.Kernel.CommandContext.t()) :: tuple()
  def list_local_users(limit, context), do: UserAccess.list(EctoIdentityStore, limit, context)

  @spec list_local_access_profiles(UokNext.Kernel.CommandContext.t()) :: tuple()
  def list_local_access_profiles(context), do: UserAccess.profiles(context)

  defp unauthorized do
    {:error, CommandError.new("unauthorized", "authentication failed", 401)}
  end
end
