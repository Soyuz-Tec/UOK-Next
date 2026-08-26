defmodule UokNext.Kernel.TenantTransaction do
  @moduledoc """
  Activates PostgreSQL row-level tenant isolation for one transaction.

  The setting is transaction-local so a pooled connection cannot retain a
  previous caller's tenant after commit or rollback.
  """

  alias UokNext.Kernel.CommandContext
  alias UokNext.Repo

  @spec run(CommandContext.t(), (-> result)) :: result when result: term()
  def run(%CommandContext{} = context, operation) when is_function(operation, 0) do
    {:ok, result} =
      Repo.transaction(fn ->
        activate!(context.tenant_id)
        operation.()
      end)

    result
  end

  @doc "Runs a tenant-scoped, repeatable-read transaction that cannot mutate data."
  @spec run_snapshot(CommandContext.t(), (-> result)) :: result when result: term()
  def run_snapshot(%CommandContext{} = context, operation) when is_function(operation, 0) do
    cond do
      sql_sandbox_snapshot?() ->
        run_nested_test_snapshot(context, operation)

      Repo.in_transaction?() ->
        raise ArgumentError, "snapshot query must begin outside an existing transaction"

      true ->
        run_isolated_snapshot(context, operation)
    end
  end

  defp run_isolated_snapshot(context, operation) do
    {:ok, result} =
      Repo.transaction(fn ->
        Repo.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY", [],
          timeout: 1_000,
          log: false
        )

        activate!(context.tenant_id)
        operation.()
      end)

    result
  end

  # The SQL sandbox wraps each database test before fixtures are inserted. It
  # cannot change those transaction characteristics later, so tests opt into
  # this path explicitly and prove the real primitive on a separate checkout.
  defp run_nested_test_snapshot(context, operation) do
    activate!(context.tenant_id)
    operation.()
  end

  defp sql_sandbox_snapshot? do
    Application.get_env(:uok_next, :allow_sql_sandbox_snapshot, false) and
      Process.get(:uok_next_force_isolated_snapshot) != true
  end

  @doc false
  @spec activate!(Ecto.UUID.t()) :: :ok
  def activate!(tenant_id) do
    {:ok, canonical_tenant_id} = Ecto.UUID.cast(tenant_id)

    case Repo.query(
           "SELECT set_config('uok.tenant_id', $1, true)",
           [canonical_tenant_id],
           timeout: 1_000,
           log: false
         ) do
      {:ok, _result} -> :ok
      {:error, error} -> raise error
    end
  end
end
