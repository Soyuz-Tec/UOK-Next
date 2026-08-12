defmodule UokNextWeb.OpenApiController do
  use UokNextWeb, :controller

  @contract_path Path.expand("../../../priv/api/openapi-v1.json", __DIR__)
  @external_resource @contract_path
  @contract @contract_path |> File.read!() |> Jason.decode!()

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "public, max-age=300")
    |> json(@contract)
  end
end
