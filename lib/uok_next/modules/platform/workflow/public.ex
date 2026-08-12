defmodule UokNext.Modules.Platform.Workflow.Public do
  @moduledoc """
  Supported boundary for governed human-task operations.

  These operations participate in the caller's command transaction; the
  coordinating business command remains responsible for audit and outbox
  records covering both its subject and the human task.
  """

  alias UokNext.Modules.Platform.Workflow.Application.HumanTasks
  alias UokNext.Modules.Platform.Workflow.Infrastructure.EctoHumanTaskStore

  @spec open_human_task(map(), UokNext.Kernel.CommandContext.t()) :: tuple()
  def open_human_task(attrs, context), do: HumanTasks.open(EctoHumanTaskStore, attrs, context)

  @spec complete_human_task(String.t(), map(), UokNext.Kernel.CommandContext.t()) :: tuple()
  def complete_human_task(task_id, attrs, context) do
    HumanTasks.complete(EctoHumanTaskStore, task_id, attrs, context)
  end
end
