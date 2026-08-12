defmodule UokNextWeb.PartyController do
  use UokNextWeb, :controller

  alias UokNext.Modules.Master.Parties.Public, as: Parties
  alias UokNext.Modules.Platform.Evidence.Public, as: Evidence
  alias UokNextWeb.{ApiResponse, RequestCommand}

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(%{assigns: %{command_context: context}} = conn, params) do
    limit = Map.get(params, "limit", "50")

    with {:ok, parsed_limit} <- RequestCommand.positive_integer(limit, :limit),
         {:ok, parties} <- Parties.list(parsed_limit, context) do
      ApiResponse.success(conn, parties)
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(%{assigns: %{command_context: context}} = conn, params) do
    case RequestCommand.idempotency_key(conn) do
      {:ok, key} ->
        ApiResponse.command(conn, Parties.create_draft(params, context, key), :created)

      {:error, error} ->
        ApiResponse.error(conn, error)
    end
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(%{assigns: %{command_context: context}} = conn, %{"id" => id}) do
    with {:ok, party} <- Parties.get(id, context),
         {:ok, evidence} <- Evidence.list_party_evidence(id, context) do
      ApiResponse.success(conn, Map.put(party, "evidence_objects", evidence))
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  @spec decide(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def decide(%{assigns: %{command_context: context}} = conn, %{"id" => id} = params) do
    with {:ok, key} <- RequestCommand.idempotency_key(conn),
         {:ok, version} <-
           RequestCommand.positive_integer(params["expected_version"], :expected_version) do
      ApiResponse.command(conn, Parties.decide(id, params, version, context, key), :ok)
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end
end
