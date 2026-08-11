defmodule UokNext.Kernel.Health do
  @moduledoc """
  Bounded liveness, startup, and readiness checks for orchestrators.
  """

  alias UokNext.Kernel.DatabaseCompatibility
  alias UokNext.Kernel.ReleaseIdentity
  alias UokNext.Repo

  @query_timeout 1_000

  @spec liveness() :: {:ok, map()}
  def liveness do
    {:ok, ReleaseIdentity.current() |> Map.put(:status, "live")}
  end

  @spec readiness(module()) :: {:ok, map()} | {:error, map()}
  def readiness(repo \\ Repo) do
    with :ok <- database_available(repo),
         :ok <- DatabaseCompatibility.verify(repo),
         :ok <- schema_current(repo) do
      {:ok, ReleaseIdentity.current() |> Map.put(:status, "ready")}
    else
      {:error, reason} ->
        {:error, %{service: "uok-next", status: "not_ready", reason: reason}}
    end
  end

  @spec startup(module()) :: {:ok, map()} | {:error, map()}
  def startup(repo \\ Repo), do: readiness(repo)

  defp database_available(repo) do
    case repo.query("SELECT 1", [], timeout: @query_timeout) do
      {:ok, _result} -> :ok
      {:error, _error} -> {:error, "database_unavailable"}
    end
  end

  defp schema_current(repo) do
    version = Application.fetch_env!(:uok_next, :required_schema_version)

    case repo.query(
           "SELECT 1 FROM schema_migrations WHERE version = $1 LIMIT 1",
           [version],
           timeout: @query_timeout
         ) do
      {:ok, %{num_rows: 1}} -> :ok
      {:ok, _result} -> {:error, "schema_not_current"}
      {:error, _error} -> {:error, "schema_unavailable"}
    end
  end
end
