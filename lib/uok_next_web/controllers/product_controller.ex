defmodule UokNextWeb.ProductController do
  use UokNextWeb, :controller

  alias UokNext.Modules.Master.Products.Public, as: Products
  alias UokNextWeb.{ApiResponse, RequestCommand}

  def index(%{assigns: %{command_context: context}} = conn, params) do
    with {:ok, limit} <- RequestCommand.positive_integer(Map.get(params, "limit", "50"), :limit),
         {:ok, products} <- Products.list(limit, context) do
      ApiResponse.success(conn, products)
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  def create(%{assigns: %{command_context: context}} = conn, params) do
    case RequestCommand.idempotency_key(conn) do
      {:ok, key} -> ApiResponse.command(conn, Products.create(params, context, key), :created)
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  def show(%{assigns: %{command_context: context}} = conn, %{"id" => id}) do
    case Products.get(id, context) do
      {:ok, product} -> ApiResponse.success(conn, product)
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end
end
