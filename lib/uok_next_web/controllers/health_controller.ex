defmodule UokNextWeb.HealthController do
  use UokNextWeb, :controller

  alias UokNext.Kernel.{Health, HealthProbe, ReleaseIdentity}

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    conn
    |> no_store()
    |> json(Map.put(ReleaseIdentity.current(), :status, "ok"))
  end

  @spec live(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def live(conn, _params), do: render_check(conn, Health.liveness())

  @spec ready(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ready(conn, _params), do: render_check(conn, HealthProbe.readiness())

  @spec startup(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def startup(conn, _params), do: render_check(conn, HealthProbe.readiness())

  @spec release(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def release(conn, _params), do: conn |> no_store() |> json(ReleaseIdentity.current())

  defp render_check(conn, {:ok, response}), do: conn |> no_store() |> json(response)

  defp render_check(conn, {:error, response}) do
    conn
    |> no_store()
    |> put_status(:service_unavailable)
    |> json(response)
  end

  defp no_store(conn), do: put_resp_header(conn, "cache-control", "no-store")
end
