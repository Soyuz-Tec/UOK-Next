defmodule UokNext.Modules.Platform.Agents.Policies.Authorization do
  @moduledoc false

  alias UokNext.Kernel.{CommandContext, CommandError}

  @spec require_permission(CommandContext.t(), String.t()) ::
          :ok | {:error, CommandError.t()}
  def require_permission(context, permission) do
    if CommandContext.permitted?(context, permission),
      do: :ok,
      else: {:error, CommandError.new("forbidden", "command is not permitted", 403)}
  end
end
