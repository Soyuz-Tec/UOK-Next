defmodule UokNextWeb.CommitmentController do
  use UokNextWeb, :controller

  alias UokNext.Modules.Trade.Contracts.Public, as: Contracts
  alias UokNextWeb.{ApiResponse, RequestCommand}

  def index(%{assigns: %{command_context: context}} = conn, params) do
    with {:ok, limit} <- RequestCommand.positive_integer(Map.get(params, "limit", "50"), :limit),
         {:ok, records} <- Contracts.list_purchase_commitment_proposals(limit, context) do
      ApiResponse.success(conn, records)
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  def create(%{assigns: %{command_context: context}} = conn, params) do
    with {:ok, key} <- RequestCommand.idempotency_key(conn),
         {:ok, version} <-
           RequestCommand.positive_integer(
             params["expected_comparison_version"],
             :expected_comparison_version
           ) do
      result = Contracts.create_purchase_commitment_proposal(params, version, context, key)
      ApiResponse.command(conn, result, :created)
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end

  def decide(%{assigns: %{command_context: context}} = conn, %{"id" => id} = params) do
    with {:ok, key} <- RequestCommand.idempotency_key(conn),
         {:ok, version} <-
           RequestCommand.positive_integer(params["expected_version"], :expected_version) do
      result = Contracts.decide_purchase_commitment_proposal(id, params, version, context, key)
      ApiResponse.command(conn, result, :ok)
    else
      {:error, error} -> ApiResponse.error(conn, error)
    end
  end
end
