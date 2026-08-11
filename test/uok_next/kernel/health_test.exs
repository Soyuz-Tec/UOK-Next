defmodule UokNext.Kernel.HealthTest do
  use ExUnit.Case, async: true

  alias UokNext.Kernel.Health

  defmodule UnavailableRepo do
    def query(_statement, _parameters, _options), do: {:error, :connection_refused}
  end

  defmodule StaleSchemaRepo do
    def query("SELECT 1", [], _options), do: {:ok, %{num_rows: 1}}
    def query(_statement, [_version], _options), do: {:ok, %{num_rows: 0}}
  end

  defmodule UnavailableSchemaRepo do
    def query("SELECT 1", [], _options), do: {:ok, %{num_rows: 1}}
    def query(_statement, [_version], _options), do: {:error, :permission_denied}
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
end
