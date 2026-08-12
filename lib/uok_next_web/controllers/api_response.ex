defmodule UokNextWeb.ApiResponse do
  @moduledoc false

  import Plug.Conn

  alias UokNext.Kernel.CommandError

  @spec success(Plug.Conn.t(), map() | [map()], atom()) :: Plug.Conn.t()
  def success(conn, data, status \\ :ok) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(status)
    |> Phoenix.Controller.json(%{data: data})
  end

  @spec command(Plug.Conn.t(), tuple(), atom()) :: Plug.Conn.t()
  def command(conn, {:ok, data, disposition}, status) do
    response_status = if disposition == :replayed, do: :ok, else: status

    conn
    |> put_resp_header("idempotency-status", Atom.to_string(disposition))
    |> success(data, response_status)
  end

  def command(conn, {:error, %CommandError{} = error}, _status), do: error(conn, error)

  @spec error(Plug.Conn.t(), CommandError.t()) :: Plug.Conn.t()
  def error(conn, error) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(error.http_status)
    |> Phoenix.Controller.json(%{
      error: %{code: error.code, message: error.message, details: error.details}
    })
  end

  @spec invalid(Plug.Conn.t(), String.t(), pos_integer()) :: Plug.Conn.t()
  def invalid(conn, message, status \\ 400) do
    error(conn, CommandError.new("invalid_request", message, status))
  end
end
