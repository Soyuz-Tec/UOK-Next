defmodule UokNextWeb.OperationalReportController do
  use UokNextWeb, :controller

  alias UokNext.Modules.Intelligence.Bi.Public, as: BusinessIntelligence
  alias UokNextWeb.{ApiResponse, RequestCommand}

  def show(%{assigns: %{command_context: context}} = conn, %{"id" => id} = params) do
    with {:ok, version} <-
           RequestCommand.positive_integer(params["expected_version"], :expected_version),
         {:ok, report} <- BusinessIntelligence.operational_report(id, version, context) do
      ApiResponse.success(conn, report)
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end
end
