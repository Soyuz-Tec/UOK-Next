defmodule UokNextWeb.ShellController do
  use UokNextWeb, :controller

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> redirect(to: "/uok-ui/index.html")
  end
end
