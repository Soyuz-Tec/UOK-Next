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
