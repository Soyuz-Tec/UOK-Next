defmodule UokNextWeb.MetricsController do
  use UokNextWeb, :controller

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    with {:ok, expected} <- configured_token(),
         {:ok, supplied} <- bearer_token(conn),
         true <- Plug.Crypto.secure_compare(supplied, expected) do
      body = TelemetryMetricsPrometheus.Core.scrape(:uok_next_metrics)

      conn
      |> put_resp_content_type("text/plain")
      |> put_resp_header("cache-control", "no-store")
      |> send_resp(:ok, body)
    else
      _failure -> send_resp(conn, :not_found, "not found")
    end
  end

  defp configured_token do
    case Application.get_env(:uok_next, :metrics_access_token) do
      token when is_binary(token) and byte_size(token) in 32..256 -> {:ok, token}
      _missing -> :error
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when byte_size(token) in 32..256 -> {:ok, token}
      _invalid -> :error
    end
  end
end
