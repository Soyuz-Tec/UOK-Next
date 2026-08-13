defmodule UokNext.Modules.Trade.Contracts.Policies.Authorization do
  @moduledoc false

  alias UokNext.Kernel.{CommandContext, CommandError}

  def require_permission(context, permission) do
    if CommandContext.permitted?(context, permission),
      do: :ok,
      else: {:error, CommandError.new("forbidden", "command is not permitted", 403)}
  end
end
