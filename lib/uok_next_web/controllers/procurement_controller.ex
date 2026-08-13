defmodule UokNextWeb.ProcurementController do
  use UokNextWeb, :controller

  alias UokNext.Modules.Trade.Sourcing.Public, as: Sourcing
  alias UokNextWeb.{ApiResponse, RequestCommand}

  def requisitions_index(conn, params), do: list(conn, params, &Sourcing.list_requisitions/2)
  def rfqs_index(conn, params), do: list(conn, params, &Sourcing.list_rfqs/2)
  def comparisons_index(conn, params), do: list(conn, params, &Sourcing.list_quote_comparisons/2)

  def quotes_index(%{assigns: %{command_context: context}} = conn, params) do
    with {:ok, limit} <- RequestCommand.positive_integer(Map.get(params, "limit", "50"), :limit),
         {:ok, records} <- Sourcing.list_supplier_quotes(params["rfq_id"], limit, context) do
      ApiResponse.success(conn, records)
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  def requisition_create(conn, params),
    do:
      create(conn, params, fn attrs, context, key ->
        Sourcing.create_requisition(attrs, context, key)
      end)

  def quote_create(conn, params),
    do:
      create(conn, params, fn attrs, context, key ->
        Sourcing.create_supplier_quote(attrs, context, key)
      end)

  def rfq_create(%{assigns: %{command_context: context}} = conn, params) do
    with {:ok, key} <- RequestCommand.idempotency_key(conn),
         {:ok, version} <-
           RequestCommand.positive_integer(params["expected_version"], :expected_version) do
      ApiResponse.command(conn, Sourcing.create_rfq(params, version, context, key), :created)
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  def comparison_create(%{assigns: %{command_context: context}} = conn, params) do
    with {:ok, key} <- RequestCommand.idempotency_key(conn),
         {:ok, version} <-
           RequestCommand.positive_integer(params["expected_version"], :expected_version) do
      result = Sourcing.create_quote_comparison(params, version, context, key)
      ApiResponse.command(conn, result, :created)
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  def comparison_decide(%{assigns: %{command_context: context}} = conn, %{"id" => id} = params) do
    with {:ok, key} <- RequestCommand.idempotency_key(conn),
         {:ok, version} <-
           RequestCommand.positive_integer(params["expected_version"], :expected_version) do
      result = Sourcing.decide_quote_comparison(id, params, version, context, key)
      ApiResponse.command(conn, result, :ok)
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  defp list(%{assigns: %{command_context: context}} = conn, params, query) do
    with {:ok, limit} <- RequestCommand.positive_integer(Map.get(params, "limit", "50"), :limit),
         {:ok, records} <- query.(limit, context) do
      ApiResponse.success(conn, records)
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  defp create(%{assigns: %{command_context: context}} = conn, params, command) do
    case RequestCommand.idempotency_key(conn) do
      {:ok, key} -> ApiResponse.command(conn, command.(params, context, key), :created)
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end
end
