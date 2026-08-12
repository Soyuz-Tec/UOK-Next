defmodule UokNextWeb.SessionController do
  use UokNextWeb, :controller

  alias UokNext.Modules.Platform.Identity.Public, as: Identity
  alias UokNextWeb.ApiResponse

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"access_code" => access_code}) do
    case Identity.authenticate_local(access_code) do
      {:ok, session} -> ApiResponse.success(conn, session, :created)
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  def create(conn, _params), do: ApiResponse.invalid(conn, "access_code is required")

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(%{assigns: %{command_context: context}} = conn, _params) do
    ApiResponse.success(conn, %{
      "tenant_id" => context.tenant_id,
      "actor_id" => context.actor_id,
      "permissions" => context.permissions |> MapSet.to_list() |> Enum.sort()
    })
  end
end
