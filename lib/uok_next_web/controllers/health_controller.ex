defmodule UokNextWeb.HealthController do
  use UokNextWeb, :controller

  alias UokNext.Kernel.ReleaseIdentity

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    json(conn, Map.put(ReleaseIdentity.current(), :status, "ok"))
  end
end
