defmodule UokNextWeb.AuthenticateAccess do
  @moduledoc false

  import Plug.Conn

  alias UokNext.Kernel.CommandContext
  alias UokNext.Modules.Platform.Identity.Public, as: Identity

  @spec init(keyword()) :: keyword()
  def init(options), do: options

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _options) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, identity} <- Identity.verify_access_token(token),
         {:ok, context} <- command_context(identity) do
      assign(conn, :command_context, context)
    else
      _failure -> reject(conn)
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when byte_size(token) in 32..2_048 -> {:ok, token}
      _invalid -> :error
    end
  end

  defp command_context(identity) do
    CommandContext.new(%{
      tenant_id: identity["tenant_id"],
      actor_id: identity["actor_id"],
      correlation_id: Ecto.UUID.generate(),
      permissions: identity["permissions"]
    })
  end

  defp reject(conn) do
    body = Jason.encode!(%{error: %{code: "unauthorized", message: "authentication failed"}})

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(401, body)
    |> halt()
  end
end
