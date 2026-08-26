defmodule UokNextWeb.MajorSeaportReferenceController do
  use UokNextWeb, :controller

  alias UokNext.Modules.Master.Locations.Public, as: Locations
  alias UokNextWeb.ApiResponse

  def countries(%{assigns: %{command_context: context}} = conn, _params) do
    case Locations.list_major_seaport_countries(context) do
      {:ok, result} -> ApiResponse.success(conn, result)
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  def index(%{assigns: %{command_context: context}} = conn, params) do
    case Locations.list_major_seaports(Map.get(params, "country_code"), context) do
      {:ok, result} -> ApiResponse.success(conn, result)
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end
end
