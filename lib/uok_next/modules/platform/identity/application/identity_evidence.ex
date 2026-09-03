defmodule UokNext.Modules.Platform.Identity.Application.IdentityEvidence do
  @moduledoc false

  @spec identity(term(), [String.t()]) :: map()
  def identity(user, permissions) do
    %{
      "tenant_id" => user.tenant_id,
      "actor_id" => user.id,
      "username" => user.username,
      "display_name" => user.display_name,
      "access_profile" => user.access_profile,
      "password_change_required" => user.must_change_password,
      "permissions" => Enum.sort(permissions)
    }
  end

  @spec user_view(term()) :: map()
  def user_view(user) do
    %{
      "id" => user.id,
      "username" => user.username,
      "display_name" => user.display_name,
      "access_profile" => user.access_profile,
      "status" => user.status,
      "must_change_password" => user.must_change_password,
      "lock_version" => user.lock_version
    }
  end

  @spec session_audit(term()) :: map()
  def session_audit(session),
    do: lifecycle_audit(session, "create_session", "Authenticated local user session")

  @spec revoke_audit(term()) :: map()
  def revoke_audit(session),
    do: lifecycle_audit(session, "revoke_session", "Signed out local user session")

  @spec session_event(term()) :: map()
  def session_event(session), do: lifecycle_event(session, "session_created")

  @spec revoke_event(term()) :: map()
  def revoke_event(session), do: lifecycle_event(session, "session_revoked")

  @spec password_audit(term()) :: map()
  def password_audit(user) do
    %{
      action: "platform.identity.activate_local_user",
      resource_type: "actor",
      resource_id: user.id,
      reason: "User replaced temporary password",
      classification: "restricted",
      metadata: %{"aggregate_version" => user.lock_version, "status" => user.status}
    }
  end

  @spec password_event(term(), term()) :: map()
  def password_event(user, credential) do
    %{
      name: "platform.identity.local_user_activated",
      aggregate_type: "actor",
      aggregate_id: user.id,
      aggregate_version: user.lock_version,
      classification: "restricted",
      payload: %{"actor_id" => user.id, "credential_generation" => credential.generation}
    }
  end

  defp lifecycle_audit(session, action, reason) do
    %{
      action: "platform.identity.#{action}",
      resource_type: "session",
      resource_id: session.id,
      reason: reason,
      classification: "restricted",
      metadata: %{"actor_id" => session.actor_id}
    }
  end

  defp lifecycle_event(session, name) do
    %{
      name: "platform.identity.#{name}",
      aggregate_type: "session",
      aggregate_id: session.id,
      aggregate_version: 1,
      classification: "restricted",
      payload: %{"actor_id" => session.actor_id, "session_id" => session.id}
    }
  end
end
