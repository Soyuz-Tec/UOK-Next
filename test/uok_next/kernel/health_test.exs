defmodule UokNext.Kernel.HealthTest do
  use ExUnit.Case, async: false

  alias UokNext.Kernel.Health

  defmodule UnavailableRepo do
    def query(_statement, _parameters, _options), do: {:error, :connection_refused}
  end

  defmodule StaleSchemaRepo do
    def query("SELECT 1", [], _options), do: {:ok, %{num_rows: 1}}

    def query(
          "SELECT current_setting('server_version_num')::integer, current_setting('server_version')",
          [],
          _options
        ),
        do: {:ok, %{rows: [[190_000, "19.0"]]}}

    def query(_statement, [_version], _options), do: {:ok, %{num_rows: 0}}
  end

  defmodule UnavailableSchemaRepo do
    def query("SELECT 1", [], _options), do: {:ok, %{num_rows: 1}}

    def query(
          "SELECT current_setting('server_version_num')::integer, current_setting('server_version')",
          [],
          _options
        ),
        do: {:ok, %{rows: [[190_000, "19.0"]]}}

    def query(_statement, [_version], _options), do: {:error, :permission_denied}
  end

  defmodule UnsupportedVersionRepo do
    def query("SELECT 1", [], _options), do: {:ok, %{num_rows: 1}}

    def query(
          "SELECT current_setting('server_version_num')::integer, current_setting('server_version')",
          [],
          _options
        ),
        do: {:ok, %{rows: [[180_004, "18.4"]]}}
  end

  defmodule PrereleaseVersionRepo do
    def query("SELECT 1", [], _options), do: {:ok, %{num_rows: 1}}

    def query(
          "SELECT current_setting('server_version_num')::integer, current_setting('server_version')",
          [],
          _options
        ),
        do: {:ok, %{rows: [[190_000, "19beta2"]]}}
  end

  defmodule ReadyRepo do
    def query("SELECT 1", [], _options), do: {:ok, %{num_rows: 1}}

    def query(
          "SELECT current_setting('server_version_num')::integer, current_setting('server_version')",
          [],
          _options
        ),
        do: {:ok, %{rows: [[190_000, "19.0"]]}}

    def query(_statement, [_version], _options), do: {:ok, %{num_rows: 1}}
  end

  test "liveness is independent from database readiness" do
    assert {:ok, %{status: "live"}} = Health.liveness()
    assert {:error, response} = Health.readiness(UnavailableRepo)
    assert response == %{service: "uok-next", status: "not_ready", reason: "database_unavailable"}
  end

  test "readiness fails closed for an unapplied required migration" do
    assert {:error, response} = Health.readiness(StaleSchemaRepo)
    assert response.reason == "schema_not_current"
  end

  test "readiness does not expose database errors" do
    assert {:error, response} = Health.readiness(UnavailableSchemaRepo)
    assert response.reason == "schema_unavailable"
    refute inspect(response) =~ "permission_denied"
  end

  test "readiness rejects a database outside the target major" do
    assert {:error, response} = Health.readiness(UnsupportedVersionRepo)
    assert response.reason == "database_version_unsupported"
  end

  test "production readiness rejects a PostgreSQL prerelease" do
    previous = Application.fetch_env!(:uok_next, :database_prerelease_allowed)
    Application.put_env(:uok_next, :database_prerelease_allowed, false)

    on_exit(fn ->
      Application.put_env(:uok_next, :database_prerelease_allowed, previous)
    end)

    assert {:error, response} = Health.readiness(PrereleaseVersionRepo)
    assert response.reason == "database_prerelease_forbidden"
  end

  test "readiness includes the durable-work repository when enabled" do
    previous = Application.fetch_env!(:uok_next, :durable_work)
    Application.put_env(:uok_next, :durable_work, Keyword.put(previous, :enabled, true))

    on_exit(fn -> Application.put_env(:uok_next, :durable_work, previous) end)

    assert {:error, response} = Health.readiness(ReadyRepo, UnavailableRepo)
    assert response.reason == "durable_work_unavailable"
  end
end
