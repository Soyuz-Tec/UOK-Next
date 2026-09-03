defmodule UokNextWeb.RequireJsonContentType do
  @moduledoc false

  import Plug.Conn
  alias Plug.Conn.Utils

  @spec init(keyword()) :: keyword()
  def init(options), do: options

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _options) do
    if json_request?(conn) do
      conn
    else
      body =
        Jason.encode!(%{
          error: %{
            code: "unsupported_media_type",
            message: "content type must be application/json"
          }
        })

      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("cache-control", "no-store")
      |> send_resp(415, body)
      |> halt()
    end
  end

  defp json_request?(conn) do
    case get_req_header(conn, "content-type") do
      [content_type] ->
        match?(
          {:ok, "application", "json", _params},
          Utils.content_type(content_type)
        )

      _missing_or_ambiguous ->
        false
    end
  end
end
