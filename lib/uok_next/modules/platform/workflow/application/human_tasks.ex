defmodule UokNext.Modules.Platform.Workflow.Application.HumanTasks do
  @moduledoc false

  alias UokNext.Kernel.{CommandContext, CommandError}
  alias UokNext.Modules.Platform.Workflow.Domain.HumanTask

  @spec open(module(), map(), CommandContext.t()) ::
          {:ok, map()} | {:error, CommandError.t()}
  def open(store, attrs, context) do
    with {:ok, task} <- validate(HumanTask.validate_open(attrs)),
         {:ok, persisted} <- create(store, task, context) do
      {:ok, view(persisted)}
    end
  end

  @spec complete(module(), String.t(), map(), CommandContext.t()) ::
          {:ok, map()} | {:error, CommandError.t()}
  def complete(store, task_id, attrs, context) do
    with {:ok, id} <- cast_uuid(task_id),
         {:ok, task} <- fetch_locked(store, id, context),
         :ok <- require_permission(context, task.required_permission),
         {:ok, completion} <- validate(HumanTask.validate_completion(task, attrs)),
         {:ok, completed} <- complete_task(store, task, completion, context) do
      {:ok, view(completed)}
    end
  end

  defp create(store, task, context) do
    attrs =
      task
      |> Map.put(:tenant_id, context.tenant_id)
      |> Map.put(:opened_by_actor_id, context.actor_id)
      |> Map.put(:opened_reason, task.reason)
      |> Map.delete(:reason)

    case store.create(attrs, context) do
      {:ok, persisted} -> {:ok, persisted}
      {:error, details} -> validation_error(details)
    end
  end

  defp fetch_locked(store, id, context) do
    case store.fetch_for_update(id, context.tenant_id, context) do
      {:ok, task} -> {:ok, task}
      :not_found -> not_found()
    end
  end

  defp complete_task(store, task, completion, context) do
    attrs = %{
      status: "completed",
      resolution: completion.resolution,
      completion_reason: completion.reason,
      completed_by_actor_id: context.actor_id,
      completed_at: DateTime.utc_now()
    }

    case store.complete(task, attrs, context) do
      {:ok, completed} -> {:ok, completed}
      {:error, :stale} -> stale()
      {:error, details} -> validation_error(details)
    end
  end

  defp require_permission(context, permission) do
    if CommandContext.permitted?(context, permission) do
      :ok
    else
      {:error, CommandError.new("forbidden", "command is not permitted", 403)}
    end
  end

  defp validate({:ok, value}), do: {:ok, value}
  defp validate({:error, details}), do: validation_error(details)

  defp cast_uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> validation_error(%{task_id: ["must be a UUID"]})
    end
  end

  defp view(task) do
    %{
      "id" => task.id,
      "tenant_id" => task.tenant_id,
      "task_kind" => task.task_kind,
      "subject_type" => task.subject_type,
      "subject_id" => task.subject_id,
      "subject_version" => task.subject_version,
      "required_permission" => task.required_permission,
      "status" => task.status,
      "resolution" => task.resolution,
      "lock_version" => task.lock_version
    }
  end

  defp validation_error(details) do
    {:error, CommandError.new("validation_failed", "human task validation failed", 422, details)}
  end

  defp stale, do: {:error, CommandError.new("stale_state", "human task changed", 409)}
  defp not_found, do: {:error, CommandError.new("not_found", "record was not found", 404)}
end
