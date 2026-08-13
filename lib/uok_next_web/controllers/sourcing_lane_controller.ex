defmodule UokNextWeb.SourcingLaneController do
  use UokNextWeb, :controller

  alias UokNext.Modules.Platform.Evidence.Public, as: Evidence
  alias UokNext.Modules.Trade.Sourcing.Public, as: Sourcing
  alias UokNextWeb.{ApiResponse, RequestCommand}

  def index(%{assigns: %{command_context: context}} = conn, params) do
    with {:ok, limit} <- RequestCommand.positive_integer(Map.get(params, "limit", "50"), :limit),
         {:ok, lanes} <- Sourcing.list(limit, context) do
      ApiResponse.success(conn, lanes)
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  def create(%{assigns: %{command_context: context}} = conn, params) do
    case RequestCommand.idempotency_key(conn) do
      {:ok, key} ->
        ApiResponse.command(conn, Sourcing.create_lane(params, context, key), :created)

      {:error, error} ->
        ApiResponse.error(conn, error)
    end
  end

  def show(%{assigns: %{command_context: context}} = conn, %{"id" => id}) do
    with {:ok, lane} <- Sourcing.get(id, context),
         {:ok, evidence} <- Evidence.list_subject_evidence("sourcing_lane", id, context) do
      ApiResponse.success(conn, Map.put(lane, "evidence_objects", evidence))
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  def decide(%{assigns: %{command_context: context}} = conn, %{"id" => id} = params) do
    with {:ok, key} <- RequestCommand.idempotency_key(conn),
         {:ok, version} <-
           RequestCommand.positive_integer(params["expected_version"], :expected_version) do
      ApiResponse.command(conn, Sourcing.decide(id, params, version, context, key), :ok)
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end
end
