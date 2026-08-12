defmodule UokNextWeb.WorkflowController do
  use UokNextWeb, :controller

  alias UokNext.Modules.Platform.Workflow.Public, as: Workflow
  alias UokNextWeb.ApiResponse

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(%{assigns: %{command_context: context}} = conn, _params) do
    case Workflow.list_open_human_tasks(context) do
      {:ok, tasks} -> ApiResponse.success(conn, tasks)
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end
end
