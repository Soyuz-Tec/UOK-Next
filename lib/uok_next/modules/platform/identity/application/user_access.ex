defmodule UokNext.Modules.Platform.Identity.Application.UserAccess do
  @moduledoc false

  alias UokNext.Kernel.{CommandContext, CommandError, CommandTransaction, TenantTransaction}
  alias UokNext.Modules.Platform.Identity.Domain.{AccessProfile, LocalUser}
  alias UokNext.Modules.Platform.Identity.Policies.Authorization

  @manage_permission "identity:users:manage"

  @spec create(module(), map(), CommandContext.t(), String.t()) :: tuple()
  def create(%{store: store, passwords: passwords}, attrs, context, idempotency_key) do
    with :ok <- Authorization.require_local_qualification(),
         :ok <- Authorization.require_permission(context, @manage_permission),
         {:ok, command} <- map_validation(LocalUser.validate_create(attrs)) do
      password_hash = passwords.hash(command.temporary_password)
      payload = safe_payload(command, passwords)

      CommandTransaction.execute(
        context,
        "platform.identity.create_local_user",
        idempotency_key,
        payload,
        fn -> create_operation(store, command, password_hash, context) end
      )
    end
  end

  @spec list(module(), pos_integer(), CommandContext.t()) :: tuple()
  def list(store, limit, context) when is_integer(limit) and limit in 1..100 do
    with :ok <- Authorization.require_local_qualification(),
         :ok <- Authorization.require_permission(context, @manage_permission) do
      TenantTransaction.run(context, fn ->
        {:ok, store.list_users(context.tenant_id, limit) |> Enum.map(&view/1)}
      end)
    end
  end

  def list(_store, _limit, _context),
    do: validation_error(%{limit: ["must be between 1 and 100"]})

  @spec profiles(CommandContext.t()) :: tuple()
  def profiles(context) do
    with :ok <- Authorization.require_local_qualification(),
         :ok <- Authorization.require_permission(context, @manage_permission) do
      {:ok, AccessProfile.all()}
    end
  end

  defp create_operation(store, command, password_hash, context) do
    attrs = %{
      tenant_id: context.tenant_id,
      username: command.username,
      normalized_username: command.normalized_username,
      display_name: command.display_name,
      access_profile: command.access_profile,
      status: "pending_activation",
      must_change_password: true
    }

    case store.create_user(attrs, password_hash) do
      {:ok, user, _credential} ->
        response = view(user)
        {:ok, response, audit(user, command.reason), [event(user)]}

      {:error, details} ->
        validation_error(details)
    end
  end

  defp safe_payload(command, passwords) do
    %{
      username: command.normalized_username,
      display_name: command.display_name,
      access_profile: command.access_profile,
      reason: command.reason,
      credential_fingerprint:
        passwords.fingerprint("local-user-create", command.temporary_password)
    }
  end

  defp view(user) do
    %{
      "id" => user.id,
      "tenant_id" => user.tenant_id,
      "username" => user.username,
      "display_name" => user.display_name,
      "access_profile" => user.access_profile,
      "status" => user.status,
      "must_change_password" => user.must_change_password,
      "lock_version" => user.lock_version
    }
  end

  defp audit(user, reason) do
    %{
      action: "platform.identity.local_user.create",
      resource_type: "actor",
      resource_id: user.id,
      reason: reason,
      classification: "restricted",
      metadata: %{
        "access_profile" => user.access_profile,
        "aggregate_version" => user.lock_version,
        "status" => user.status
      }
    }
  end

  defp event(user) do
    %{
      name: "platform.identity.local_user_created",
      aggregate_type: "actor",
      aggregate_id: user.id,
      aggregate_version: user.lock_version,
      classification: "restricted",
      payload: %{
        "actor_id" => user.id,
        "access_profile" => user.access_profile,
        "status" => user.status
      }
    }
  end

  defp map_validation({:ok, value}), do: {:ok, value}
  defp map_validation({:error, details}), do: validation_error(details)

  defp validation_error(details) do
    {:error, CommandError.new("validation_failed", "user validation failed", 422, details)}
  end
end
