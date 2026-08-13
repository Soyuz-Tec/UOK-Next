defmodule UokNextWeb.LocationController do
  use UokNextWeb, :controller

  alias UokNext.Modules.Master.Locations.Public, as: Locations
  alias UokNextWeb.{ApiResponse, RequestCommand}

  def index(%{assigns: %{command_context: context}} = conn, params) do
    with {:ok, limit} <- RequestCommand.positive_integer(Map.get(params, "limit", "50"), :limit),
         {:ok, locations} <- Locations.list(limit, context) do
      ApiResponse.success(conn, locations)
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  def create(%{assigns: %{command_context: context}} = conn, params) do
    case RequestCommand.idempotency_key(conn) do
      {:ok, key} -> ApiResponse.command(conn, Locations.create(params, context, key), :created)
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  def show(%{assigns: %{command_context: context}} = conn, %{"id" => id}) do
    case Locations.get(id, context) do
      {:ok, location} -> ApiResponse.success(conn, location)
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end
end
