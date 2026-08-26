defmodule UokNext.Kernel.TenantTransactionSnapshotTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias UokNext.Kernel.{AuditEvent, TenantTransaction}
  alias UokNext.ProcurementFixtures
  alias UokNext.Repo

  test "a top-level snapshot is repeatable-read, read-only, and tenant-scoped" do
    context = ProcurementFixtures.context()
    tenant_id = context.tenant_id

    task =
      Task.async(fn ->
        :ok = Sandbox.checkout(Repo, sandbox: false)
        Process.put(:uok_next_force_isolated_snapshot, true)

        try do
          settings =
            TenantTransaction.run_snapshot(context, fn ->
              %{
                isolation: Repo.query!("SHOW transaction_isolation", []).rows,
                read_only: Repo.query!("SHOW transaction_read_only", []).rows,
                tenant: Repo.query!("SELECT current_setting('uok.tenant_id', true)", []).rows
              }
            end)

          write_result =
            try do
              TenantTransaction.run_snapshot(context, fn ->
                Repo.insert!(%AuditEvent{
                  tenant_id: context.tenant_id,
                  actor_id: context.actor_id,
                  correlation_id: context.correlation_id,
                  action: "test.write",
                  resource_type: "test_record",
                  resource_id: Ecto.UUID.generate(),
                  reason: "Prove report transaction is read only",
                  outcome: "succeeded",
                  classification: "internal",
                  metadata: %{}
                })

                :unexpected_write
              end)
            rescue
              error in Postgrex.Error -> error.postgres.code
            end

          Map.put(settings, :write, write_result)
        after
          Sandbox.checkin(Repo)
        end
      end)

    assert %{
             isolation: [["repeatable read"]],
             read_only: [["on"]],
             tenant: [[^tenant_id]],
             write: :read_only_sql_transaction
           } = Task.await(task, 10_000)
  end
end
