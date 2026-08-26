defmodule UokNextWeb.LocalUserController do
  use UokNextWeb, :controller

  alias UokNext.Modules.Platform.Identity.Public, as: Identity
  alias UokNextWeb.{ApiResponse, RequestCommand}

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(%{assigns: %{command_context: context}} = conn, params) do
    with {:ok, limit} <- RequestCommand.positive_integer(Map.get(params, "limit", "100"), :limit),
         {:ok, users} <- Identity.list_local_users(limit, context) do
      ApiResponse.success(conn, users)
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(%{assigns: %{command_context: context}} = conn, params) do
    case RequestCommand.idempotency_key(conn) do
      {:ok, key} ->
        ApiResponse.command(conn, Identity.create_local_user(params, context, key), :created)

      {:error, error} ->
        ApiResponse.error(conn, error)
    end
  end

  @spec profiles(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def profiles(%{assigns: %{command_context: context}} = conn, _params) do
    case Identity.list_local_access_profiles(context) do
      {:ok, profiles} -> ApiResponse.success(conn, profiles)
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end
end
