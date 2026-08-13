defmodule UokNextWeb.ReadinessController do
  use UokNextWeb, :controller

  alias UokNext.Modules.Trade.Shipments.Public, as: Shipments
  alias UokNextWeb.{ApiResponse, RequestCommand}

  def index(%{assigns: %{command_context: context}} = conn, params) do
    with {:ok, limit} <- RequestCommand.positive_integer(Map.get(params, "limit", "50"), :limit),
         {:ok, records} <- Shipments.list_readiness_cases(limit, context) do
      ApiResponse.success(conn, records)
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  def create(%{assigns: %{command_context: context}} = conn, params) do
    with {:ok, key} <- RequestCommand.idempotency_key(conn),
         {:ok, version} <-
           RequestCommand.positive_integer(
             params["expected_proposal_version"],
             :expected_proposal_version
           ) do
      result = Shipments.create_readiness_case(params, version, context, key)
      ApiResponse.command(conn, result, :created)
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  def decide(%{assigns: %{command_context: context}} = conn, %{"id" => id} = params) do
    with {:ok, key} <- RequestCommand.idempotency_key(conn),
         {:ok, version} <-
           RequestCommand.positive_integer(params["expected_version"], :expected_version) do
      result = Shipments.decide_readiness(id, Map.delete(params, "id"), version, context, key)
      ApiResponse.command(conn, result, :ok)
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end
end
