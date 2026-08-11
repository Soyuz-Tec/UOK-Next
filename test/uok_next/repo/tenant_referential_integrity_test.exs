defmodule UokNext.Repo.TenantReferentialIntegrityTest do
  use UokNext.DataCase, async: false

  test "audit events cannot reference a command receipt from another tenant" do
    receipt_id = insert_receipt()

    error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          """
          INSERT INTO kernel_audit_events (
            id, tenant_id, actor_id, correlation_id, command_receipt_id,
            action, resource_type, resource_id, outcome, reason,
            classification, metadata, occurred_at, inserted_at
          ) VALUES (
            $1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::uuid,
            'test.audit', 'test_resource', $6::uuid, 'rejected', 'constraint proof',
            'internal', '{}'::jsonb, now(), now()
          )
          """,
          [uuid(), uuid(), uuid(), uuid(), receipt_id, uuid()]
        )
      end

    assert error.postgres.code == :foreign_key_violation
    assert error.postgres.constraint == "kernel_audit_events_tenant_receipt_fkey"
  end

  test "outbox events cannot reference a command receipt from another tenant" do
    receipt_id = insert_receipt()

    error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          """
          INSERT INTO kernel_outbox_events (
            id, tenant_id, actor_id, correlation_id, command_receipt_id,
            event_name, event_version, aggregate_type, aggregate_id,
            aggregate_version, classification, payload, status, available_at,
            attempt_count, inserted_at, updated_at
          ) VALUES (
            $1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::uuid,
            'test.event', 1, 'test_resource', $6::uuid,
            1, 'internal', '{}'::jsonb, 'pending', now(),
            0, now(), now()
          )
          """,
          [uuid(), uuid(), uuid(), uuid(), receipt_id, uuid()]
        )
      end

    assert error.postgres.code == :foreign_key_violation
    assert error.postgres.constraint == "kernel_outbox_events_tenant_receipt_fkey"
  end

  defp insert_receipt do
    receipt_id = uuid()

    Repo.query!(
      """
      INSERT INTO kernel_command_receipts (
        id, tenant_id, actor_id, correlation_id, idempotency_key,
        command_name, payload_hash, status, inserted_at, updated_at
      ) VALUES (
        $1::uuid, $2::uuid, $3::uuid, $4::uuid, $5,
        'test.command', decode('00', 'hex'), 'completed', now(), now()
      )
      """,
      [receipt_id, uuid(), uuid(), uuid(), Ecto.UUID.generate()]
    )

    receipt_id
  end

  defp uuid, do: Ecto.UUID.bingenerate()
end
