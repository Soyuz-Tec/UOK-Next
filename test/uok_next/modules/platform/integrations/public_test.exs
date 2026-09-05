defmodule UokNext.Modules.Platform.Integrations.PublicTest do
  use UokNext.DataCase, async: true

  alias UokNext.Kernel.{
    AuditEvent,
    CommandContext,
    CommandReceipt,
    OutboxEvent,
    TenantTransaction
  }

  alias UokNext.Modules.Platform.Integrations.Infrastructure.ConnectorReceiptRecord
  alias UokNext.Modules.Platform.Integrations.Public

  describe "connector receipt lifecycle" do
    test "atomically records and reconciles bounded connector evidence" do
      context = context()

      assert {:ok, attempted, :executed} =
               Public.begin_attempt(attempt_attrs(), context, Ecto.UUID.generate())

      assert attempted["status"] == "attempted"
      assert attempted["attempt_number"] == 1
      assert attempted["lock_version"] == 1
      assert counts(context) == %{receipts: 1, commands: 1, audits: 1, events: 1}

      outcome = %{
        "status" => "succeeded",
        "response_sha256" => String.duplicate("b", 64),
        "external_reference" => "external-ref-1207",
        "reason" => "Remote system acknowledged the request"
      }

      assert {:ok, reconciled, :executed} =
               Public.reconcile(
                 attempted["id"],
                 attempted["lock_version"],
                 outcome,
                 context,
                 Ecto.UUID.generate()
               )

      assert reconciled["status"] == "succeeded"
      assert reconciled["response_sha256"] == String.duplicate("b", 64)
      assert reconciled["external_reference"] == "external-ref-1207"
      assert reconciled["lock_version"] == 2
      assert counts(context) == %{receipts: 1, commands: 2, audits: 2, events: 2}
    end

    test "replays safely and rejects idempotency-key input substitution" do
      context = context()
      attrs = attempt_attrs()
      key = Ecto.UUID.generate()

      assert {:ok, first, :executed} = Public.begin_attempt(attrs, context, key)
      assert {:ok, ^first, :replayed} = Public.begin_attempt(attrs, context, key)

      substituted = Map.put(attrs, "request_sha256", String.duplicate("c", 64))
      assert {:error, conflict} = Public.begin_attempt(substituted, context, key)
      assert conflict.code == "idempotency_conflict"
      assert counts(context) == %{receipts: 1, commands: 1, audits: 1, events: 1}
    end

    test "rejects duplicate delivery attempts and rolls back their command evidence" do
      context = context()
      attrs = attempt_attrs()

      assert {:ok, _receipt, :executed} =
               Public.begin_attempt(attrs, context, Ecto.UUID.generate())

      assert {:error, duplicate} = Public.begin_attempt(attrs, context, Ecto.UUID.generate())
      assert duplicate.code == "validation_failed"
      assert counts(context) == %{receipts: 1, commands: 1, audits: 1, events: 1}
    end

    test "permits a matching retry only after a retryable outcome" do
      context = context()
      attrs = attempt_attrs()
      attempted = begin_attempt(attrs, context)

      outcome = %{
        "status" => "retryable_failure",
        "retry_after_seconds" => 30,
        "reason" => "Remote system requested bounded backoff"
      }

      assert {:ok, failed, :executed} =
               Public.reconcile(
                 attempted["id"],
                 attempted["lock_version"],
                 outcome,
                 context,
                 Ecto.UUID.generate()
               )

      retry_attrs = Map.put(attrs, "previous_receipt_id", failed["id"])

      assert {:ok, retry, :executed} =
               Public.begin_attempt(retry_attrs, context, Ecto.UUID.generate())

      assert retry["attempt_number"] == 2
      assert retry["previous_receipt_id"] == failed["id"]

      changed = Map.put(retry_attrs, "request_sha256", String.duplicate("d", 64))
      assert {:error, mismatch} = Public.begin_attempt(changed, context, Ecto.UUID.generate())
      assert mismatch.code == "validation_failed"
      assert tenant_count(ConnectorReceiptRecord, context) == 2
    end

    test "rejects retry after success" do
      context = context()
      attrs = attempt_attrs()
      attempted = begin_attempt(attrs, context)

      assert {:ok, succeeded, :executed} =
               Public.reconcile(
                 attempted["id"],
                 attempted["lock_version"],
                 success_outcome(),
                 context,
                 Ecto.UUID.generate()
               )

      retry_attrs = Map.put(attrs, "previous_receipt_id", succeeded["id"])
      assert {:error, rejected} = Public.begin_attempt(retry_attrs, context, Ecto.UUID.generate())
      assert rejected.code == "validation_failed"
      assert tenant_count(ConnectorReceiptRecord, context) == 1
    end

    test "uses the server deadline for timeout and supports recovery retry" do
      context = context()
      attrs = attempt_attrs(%{"timeout_ms" => 120_000})
      attempted = begin_attempt(attrs, context)

      assert {:error, early} =
               Public.reconcile(
                 attempted["id"],
                 attempted["lock_version"],
                 timeout_outcome(),
                 context,
                 Ecto.UUID.generate()
               )

      assert early.code == "validation_failed"
      expire(attempted["id"], context)

      assert {:error, late_success} =
               Public.reconcile(
                 attempted["id"],
                 attempted["lock_version"],
                 success_outcome(),
                 context,
                 Ecto.UUID.generate()
               )

      assert late_success.code == "validation_failed"

      assert {:ok, timed_out, :executed} =
               Public.reconcile(
                 attempted["id"],
                 attempted["lock_version"],
                 timeout_outcome(),
                 context,
                 Ecto.UUID.generate()
               )

      retry_attrs = Map.put(attrs, "previous_receipt_id", timed_out["id"])

      assert {:ok, retry, :executed} =
               Public.begin_attempt(retry_attrs, context, Ecto.UUID.generate())

      assert retry["attempt_number"] == 2
    end

    test "rejects stale reconciliation and raw response storage" do
      context = context()
      attempted = begin_attempt(attempt_attrs(), context)

      assert {:error, stale} =
               Public.reconcile(
                 attempted["id"],
                 attempted["lock_version"] + 1,
                 success_outcome(),
                 context,
                 Ecto.UUID.generate()
               )

      assert stale.code == "stale_state"

      raw = Map.put(success_outcome(), "response_body", "sensitive remote payload")

      assert {:error, rejected} =
               Public.reconcile(
                 attempted["id"],
                 attempted["lock_version"],
                 raw,
                 context,
                 Ecto.UUID.generate()
               )

      assert rejected.code == "validation_failed"
      persisted = tenant_one(ConnectorReceiptRecord, context)
      assert persisted.status == "attempted"
      assert persisted.response_sha256 == nil
      assert counts(context) == %{receipts: 1, commands: 1, audits: 1, events: 1}
    end
  end

  describe "authorization and tenant isolation" do
    test "denies each operation without its named permission" do
      denied = context(%{permissions: []})

      assert {:error, attempt_denied} =
               Public.begin_attempt(attempt_attrs(), denied, Ecto.UUID.generate())

      assert attempt_denied.code == "forbidden"

      owner = context()
      attempted = begin_attempt(attempt_attrs(), owner)
      read_only = context(%{tenant_id: owner.tenant_id, permissions: ["integrations:read"]})

      assert {:error, reconcile_denied} =
               Public.reconcile(
                 attempted["id"],
                 attempted["lock_version"],
                 success_outcome(),
                 read_only,
                 Ecto.UUID.generate()
               )

      assert reconcile_denied.code == "forbidden"
      no_read = context(%{tenant_id: owner.tenant_id, permissions: ["integrations:attempt"]})
      assert {:error, read_denied} = Public.get(attempted["id"], no_read)
      assert read_denied.code == "forbidden"
    end

    test "hides a foreign tenant receipt and retry lineage" do
      owner = context()
      other = context()
      attempted = begin_attempt(attempt_attrs(), owner)

      assert {:error, hidden} = Public.get(attempted["id"], other)
      assert hidden.code == "not_found"

      retry_attrs = attempt_attrs(%{"previous_receipt_id" => attempted["id"]})
      assert {:error, hidden} = Public.begin_attempt(retry_attrs, other, Ecto.UUID.generate())
      assert hidden.code == "not_found"
      assert tenant_count(ConnectorReceiptRecord, owner) == 1
      assert tenant_count(ConnectorReceiptRecord, other) == 0
    end

    test "forced row-level security rejects unset and substituted tenant state" do
      owner = context()
      other = context()
      _attempted = begin_attempt(attempt_attrs(), owner)

      Repo.query!("SET LOCAL ROLE pg_read_all_data", [], log: false)
      Repo.query!("SELECT set_config('uok.tenant_id', '', true)", [], log: false)
      assert Repo.aggregate(ConnectorReceiptRecord, :count) == 0
      assert tenant_count(ConnectorReceiptRecord, other) == 0
      assert tenant_count(ConnectorReceiptRecord, owner) == 1
    end
  end

  defp context(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          tenant_id: Ecto.UUID.generate(),
          actor_id: Ecto.UUID.generate(),
          correlation_id: Ecto.UUID.generate(),
          permissions: ["integrations:attempt", "integrations:reconcile", "integrations:read"]
        },
        overrides
      )

    {:ok, context} = CommandContext.new(attrs)
    context
  end

  defp attempt_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "connector_role" => "contract_system",
        "operation" => "deliver_notice",
        "delivery_key" => "delivery-#{System.unique_integer([:positive])}",
        "request_sha256" => String.duplicate("a", 64),
        "subject_type" => "party",
        "subject_id" => Ecto.UUID.generate(),
        "subject_version" => 1,
        "timeout_ms" => 30_000,
        "reason" => "Record governed outbound connector attempt"
      },
      overrides
    )
  end

  defp success_outcome do
    %{
      "status" => "succeeded",
      "response_sha256" => String.duplicate("b", 64),
      "reason" => "Remote system acknowledged the request"
    }
  end

  defp timeout_outcome do
    %{
      "status" => "timed_out",
      "retry_after_seconds" => 15,
      "reason" => "Server deadline elapsed without a response"
    }
  end

  defp begin_attempt(attrs, context) do
    {:ok, receipt, :executed} = Public.begin_attempt(attrs, context, Ecto.UUID.generate())
    receipt
  end

  defp expire(receipt_id, context) do
    TenantTransaction.run(context, fn ->
      Repo.update_all(
        from(receipt in ConnectorReceiptRecord, where: receipt.id == ^receipt_id),
        set: [deadline_at: DateTime.add(DateTime.utc_now(), -1, :second)]
      )
    end)
  end

  defp counts(context) do
    %{
      receipts: tenant_count(ConnectorReceiptRecord, context),
      commands: tenant_count(CommandReceipt, context),
      audits: tenant_count(AuditEvent, context),
      events: tenant_count(OutboxEvent, context)
    }
  end

  defp tenant_count(schema, context) do
    TenantTransaction.run(context, fn ->
      Repo.aggregate(
        from(record in schema, where: record.tenant_id == ^context.tenant_id),
        :count
      )
    end)
  end

  defp tenant_one(schema, context) do
    TenantTransaction.run(context, fn ->
      Repo.one!(from(record in schema, where: record.tenant_id == ^context.tenant_id))
    end)
  end
end
