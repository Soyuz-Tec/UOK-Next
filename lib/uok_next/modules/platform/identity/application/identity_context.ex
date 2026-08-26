defmodule UokNext.Modules.Platform.Identity.Application.IdentityContext do
  @moduledoc false

  alias UokNext.Kernel.CommandContext

  @spec local_tenant_id() :: {:ok, Ecto.UUID.t()} | :error
  def local_tenant_id do
    case Application.get_env(:uok_next, :local_qualification_identity) do
      %{tenant_id: tenant_id} -> Ecto.UUID.cast(tenant_id)
      _missing -> :error
    end
  end

  @spec lookup(Ecto.UUID.t()) :: CommandContext.t()
  def lookup(tenant_id) do
    identity = Application.fetch_env!(:uok_next, :local_qualification_identity)

    {:ok, context} =
      CommandContext.new(%{
        tenant_id: tenant_id,
        actor_id: identity.actor_id,
        correlation_id: Ecto.UUID.generate(),
        permissions: []
      })

    context
  end

  @spec for_user(term(), [String.t()]) :: {:ok, CommandContext.t()}
  def for_user(user, permissions) do
    CommandContext.new(%{
      tenant_id: user.tenant_id,
      actor_id: user.id,
      correlation_id: Ecto.UUID.generate(),
      permissions: permissions
    })
  end

  @spec for_bootstrap(map()) :: {:ok, CommandContext.t()}
  def for_bootstrap(identity) do
    CommandContext.new(%{
      tenant_id: identity.tenant_id,
      actor_id: identity.actor_id,
      correlation_id: Ecto.UUID.generate(),
      permissions: identity.permissions
    })
  end
end
