defmodule UokNext.Modules.Master.Locations.Application.Locations do
  @moduledoc false

  alias UokNext.Kernel.{CommandContext, CommandError, CommandTransaction, TenantTransaction}
  alias UokNext.Modules.Master.Locations.Domain.Location
  alias UokNext.Modules.Master.Locations.Policies.Authorization

  @create_permission "locations:create"
  @read_permission "locations:read"

  @spec create(module(), map(), CommandContext.t(), String.t()) :: tuple()
  def create(store, attrs, context, idempotency_key) do
    with :ok <- Authorization.require_permission(context, @create_permission),
         {:ok, command} <- validate(Location.validate_create(attrs)) do
      payload = Map.put(command, :tenant_id, context.tenant_id)

      CommandTransaction.execute(
        context,
        "master.locations.create",
        idempotency_key,
        payload,
        fn -> create_operation(store, command, context) end
      )
    end
  end

  @spec get(module(), String.t(), CommandContext.t()) :: tuple()
  def get(store, location_id, context) do
    with :ok <- Authorization.require_permission(context, @read_permission),
         {:ok, id} <- cast_uuid(location_id) do
      TenantTransaction.run(context, fn -> fetch_view(store, id, context) end)
    end
  end

  @spec require_active(module(), String.t(), CommandContext.t()) :: tuple()
  def require_active(store, location_id, context) do
    with {:ok, location} <- get(store, location_id, context),
         true <- location["status"] == "active" do
      {:ok, location}
    else
      false -> not_found()
      {:error, %CommandError{} = error} -> {:error, error}
    end
  end

  @spec list(module(), pos_integer(), CommandContext.t()) :: tuple()
  def list(store, limit, context) when is_integer(limit) and limit in 1..100 do
    with :ok <- Authorization.require_permission(context, @read_permission) do
      TenantTransaction.run(context, fn ->
        {:ok, store.list(context.tenant_id, limit, context) |> Enum.map(&view/1)}
      end)
    end
  end

  def list(_store, _limit, _context), do: validation_error(%{limit: ["must be 1 to 100"]})

  defp create_operation(store, command, context) do
    attrs = command |> Map.delete(:reason) |> Map.put(:tenant_id, context.tenant_id)

    case store.create(attrs, context) do
      {:ok, location} ->
        {:ok, view(location), audit(location, command.reason), [event(location)]}

      {:error, details} ->
        validation_error(details)
    end
  end

  defp fetch_view(store, id, context) do
    case store.fetch(id, context.tenant_id, context) do
      {:ok, location} -> {:ok, view(location)}
      :not_found -> not_found()
    end
  end

  defp view(location) do
    %{
      "id" => location.id,
      "tenant_id" => location.tenant_id,
      "stable_identifier" => location.stable_identifier,
      "name" => location.name,
      "country_code" => location.country_code,
      "location_kind" => location.location_kind,
      "status" => location.status,
      "lock_version" => location.lock_version
    }
  end

  defp audit(location, reason) do
    %{
      action: "master.locations.create",
      resource_type: "location",
      resource_id: location.id,
      reason: reason,
      classification: "internal",
      metadata: %{"status" => location.status, "aggregate_version" => location.lock_version}
    }
  end

  defp event(location) do
    %{
      name: "master.locations.location_created",
      aggregate_type: "location",
      aggregate_id: location.id,
      aggregate_version: location.lock_version,
      classification: "internal",
      payload: %{"location_id" => location.id, "status" => location.status}
    }
  end

  defp cast_uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> validation_error(%{location_id: ["must be a UUID"]})
    end
  end

  defp validate({:ok, value}), do: {:ok, value}
  defp validate({:error, details}), do: validation_error(details)

  defp validation_error(details),
    do:
      {:error, CommandError.new("validation_failed", "location validation failed", 422, details)}

  defp not_found, do: {:error, CommandError.new("not_found", "record was not found", 404)}
end
