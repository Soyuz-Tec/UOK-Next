defmodule UokNextWeb.CommunicationsController do
  use UokNextWeb, :controller

  alias UokNext.Kernel.CommandError
  alias UokNext.Modules.Platform.Integrations.Public, as: Integrations
  alias UokNextWeb.{ApiResponse, RequestCommand}

  @spec health(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def health(%{assigns: %{command_context: context}} = conn, _params) do
    case Integrations.communications_health(context) do
      {:ok, health} -> ApiResponse.success(conn, health)
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(%{assigns: %{command_context: context}} = conn, params) do
    case RequestCommand.idempotency_key(conn) do
      {:ok, key} ->
        ApiResponse.command(conn, Integrations.link_communication(params, context, key), :created)

      {:error, error} ->
        ApiResponse.error(conn, error)
    end
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(%{assigns: %{command_context: context}} = conn, %{"id" => id}) do
    case Integrations.get_communication_link(id, context) do
      {:ok, link} -> ApiResponse.success(conn, link)
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  @spec request_delivery(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def request_delivery(%{assigns: %{command_context: context}} = conn, %{"id" => id} = params) do
    with {:ok, key} <- RequestCommand.idempotency_key(conn),
         {:ok, version} <-
           RequestCommand.positive_integer(params["expected_version"], :expected_version) do
      attrs = Map.drop(params, ["id", "expected_version"])
      result = Integrations.request_communication_delivery(id, attrs, version, context, key)
      ApiResponse.command(conn, result, :created)
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  @spec reconcile_delivery(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def reconcile_delivery(%{assigns: %{command_context: context}} = conn, params) do
    with {:ok, key} <- RequestCommand.idempotency_key(conn),
         {:ok, version} <-
           RequestCommand.positive_integer(params["expected_version"], :expected_version),
         :ok <- reconciliation_fields(params) do
      result =
        Integrations.reconcile_communication_delivery(
          params["id"],
          params["receipt_id"],
          version,
          context,
          key
        )

      ApiResponse.command(conn, result, :ok)
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  defp reconciliation_fields(params) do
    if map_size(Map.drop(params, ["id", "receipt_id", "expected_version"])) == 0 do
      :ok
    else
      {:error,
       CommandError.new(
         "invalid_request",
         "reconciliation accepts only expected_version",
         400
       )}
    end
  end
end
