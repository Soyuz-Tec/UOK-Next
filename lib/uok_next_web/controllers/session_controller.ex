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

  def create(conn, %{"username" => _username, "password" => _password} = params) do
    case Identity.authenticate_password(params) do
      {:ok, session} -> ApiResponse.success(conn, session, :created)
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  def create(conn, _params),
    do: ApiResponse.invalid(conn, "username and password or a local access code are required")

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(%{assigns: %{authenticated_identity: identity}} = conn, _params) do
    ApiResponse.success(conn, identity)
  end

  @spec change_password(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def change_password(%{assigns: %{command_context: context}} = conn, params) do
    case UokNextWeb.RequestCommand.idempotency_key(conn) do
      {:ok, key} -> ApiResponse.command(conn, Identity.change_password(params, context, key), :ok)
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(%{assigns: %{command_context: context, access_token: token}} = conn, _params) do
    ApiResponse.command(conn, Identity.revoke_access_token(token, context), :ok)
  end
end
