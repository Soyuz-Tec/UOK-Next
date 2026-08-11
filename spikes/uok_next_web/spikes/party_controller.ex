defmodule UokNextWeb.Spikes.PartyController do
  @moduledoc false

  use UokNextWeb, :controller

  alias UokNext.Kernel.{CommandContext, CommandError}

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"implementation" => implementation} = params) do
    with {:ok, backend} <- backend(implementation),
         {:ok, context} <- context(conn),
         {:ok, idempotency_key} <- idempotency_key(conn),
         {:ok, response, disposition} <-
           backend.create_draft(Map.drop(params, ["implementation"]), context, idempotency_key) do
      conn
      |> put_status(if(disposition == :executed, do: :created, else: :ok))
      |> put_resp_header("cache-control", "no-store")
      |> json(%{"data" => response, "disposition" => Atom.to_string(disposition)})
    else
      {:error, error} -> render_error(conn, error)
    end
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"implementation" => implementation, "id" => id}) do
    with {:ok, backend} <- backend(implementation),
         {:ok, context} <- context(conn),
         {:ok, response} <- backend.get(id, context) do
      conn
      |> put_resp_header("cache-control", "no-store")
      |> json(%{"data" => response})
    else
      {:error, error} -> render_error(conn, error)
    end
  end

  @spec submit_evidence(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def submit_evidence(conn, params) do
    command(conn, params, fn backend, id, body, version, context, key ->
      backend.submit_evidence(id, body, version, context, key)
    end)
  end

  @spec decide(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def decide(conn, params) do
    command(conn, params, fn backend, id, body, version, context, key ->
      backend.decide(id, body, version, context, key)
    end)
  end

  defp command(conn, %{"implementation" => implementation, "id" => id} = params, execute) do
    with {:ok, backend} <- backend(implementation),
         {:ok, context} <- context(conn),
         {:ok, key} <- idempotency_key(conn),
         {:ok, version} <- expected_version(params),
         {:ok, response, disposition} <-
           execute.(backend, id, command_body(params), version, context, key) do
      conn
      |> put_resp_header("cache-control", "no-store")
      |> json(%{"data" => response, "disposition" => Atom.to_string(disposition)})
    else
      {:error, error} -> render_error(conn, error)
    end
  end

  defp backend("explicit"), do: {:ok, UokNext.Modules.Master.Parties.Public}

  defp backend(_implementation) do
    {:error, CommandError.new("not_found", "spike implementation was not found", 404)}
  end

  defp context(conn) do
    permissions =
      conn
      |> get_req_header("x-uok-test-permissions")
      |> List.first("")
      |> String.split(",", trim: true)

    CommandContext.new(%{
      tenant_id: first_header(conn, "x-uok-test-tenant-id"),
      actor_id: first_header(conn, "x-uok-test-actor-id"),
      correlation_id: first_header(conn, "x-uok-test-correlation-id"),
      permissions: permissions
    })
  end

  defp idempotency_key(conn) do
    case first_header(conn, "idempotency-key") do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, CommandError.new("invalid_idempotency_key", "idempotency key is required", 400)}
    end
  end

  defp expected_version(%{"expected_version" => version}) when is_integer(version), do: {:ok, version}

  defp expected_version(_params) do
    {:error, CommandError.new("validation_failed", "expected_version is required", 422)}
  end

  defp command_body(params), do: Map.drop(params, ["implementation", "id", "expected_version"])
  defp first_header(conn, name), do: conn |> get_req_header(name) |> List.first()

  defp render_error(conn, %CommandError{} = error) do
    conn
    |> put_status(error.http_status)
    |> put_resp_header("cache-control", "no-store")
    |> json(%{
      "error" => %{
        "code" => error.code,
        "message" => error.message,
        "details" => error.details
      }
    })
  end
end
