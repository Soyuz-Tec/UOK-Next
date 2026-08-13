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

  test "a sourcing lane cannot reference product authority from another tenant" do
    tenant_id = uuid()
    other_tenant_id = uuid()
    supplier_id = uuid()
    product_id = uuid()
    origin_id = uuid()
    destination_id = uuid()

    insert_party(tenant_id, supplier_id)
    insert_product(other_tenant_id, product_id)
    insert_location(tenant_id, origin_id, "origin")
    insert_location(tenant_id, destination_id, "destination")

    error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          """
          INSERT INTO trade_sourcing_lanes (
            id, tenant_id, stable_identifier, name, supplier_party_id, product_id,
            origin_location_id, destination_location_id, status, lock_version,
            inserted_at, updated_at
          ) VALUES ($1, $2, 'cross-tenant-lane', 'Cross tenant lane', $3, $4, $5, $6,
                    'draft', 1, now(), now())
          """,
          [uuid(), tenant_id, supplier_id, product_id, origin_id, destination_id]
        )
      end

    assert error.postgres.code == :foreign_key_violation
    assert error.postgres.constraint == "trade_sourcing_lanes_tenant_product_fkey"
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

  defp insert_party(tenant_id, id) do
    Repo.query!(
      """
      INSERT INTO master_parties (
        id, tenant_id, stable_identifier, legal_name, country_code, party_kind,
        status, lock_version, inserted_at, updated_at
      ) VALUES ($1, $2, $3, 'Approved Supplier', 'GH', 'organization',
                'approved', 1, now(), now())
      """,
      [id, tenant_id, "supplier-#{Ecto.UUID.generate()}"]
    )
  end

  defp insert_product(tenant_id, id) do
    Repo.query!(
      """
      INSERT INTO master_products (
        id, tenant_id, stable_identifier, name, product_kind, base_unit_code,
        status, lock_version, inserted_at, updated_at
      ) VALUES ($1, $2, $3, 'Product', 'commodity', 'MT', 'active', 1, now(), now())
      """,
      [id, tenant_id, "product-#{Ecto.UUID.generate()}"]
    )
  end

  defp insert_location(tenant_id, id, label) do
    Repo.query!(
      """
      INSERT INTO master_locations (
        id, tenant_id, stable_identifier, name, country_code, location_kind,
        status, lock_version, inserted_at, updated_at
      ) VALUES ($1, $2, $3, $4, 'GH', 'port', 'active', 1, now(), now())
      """,
      [id, tenant_id, "#{label}-#{Ecto.UUID.generate()}", "#{label} location"]
    )
  end

  defp uuid, do: Ecto.UUID.bingenerate()
end
