defmodule UokNext.Modules.Platform.Identity.Policies.Authorization do
  @moduledoc false

  alias UokNext.Kernel.{CommandContext, CommandError}

  @spec require_permission(CommandContext.t(), String.t()) ::
          :ok | {:error, CommandError.t()}
  def require_permission(context, permission) do
    if CommandContext.permitted?(context, permission) do
      :ok
    else
      {:error, CommandError.new("forbidden", "command is not permitted", 403)}
    end
  end

  @spec require_local_qualification() :: :ok | {:error, CommandError.t()}
  def require_local_qualification do
    if Application.get_env(:uok_next, :deployment_profile) == :local_qualification do
      :ok
    else
      {:error, CommandError.new("not_found", "resource was not found", 404)}
    end
  end
end
