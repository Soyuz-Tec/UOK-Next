defmodule UokNext.Kernel.DurableWorkTest do
  use UokNext.DataCase, async: false

  import Ecto.Query

  alias UokNext.Kernel.{
    CommandTransaction,
    DurableJob,
    DurableWork,
    OutboxDelivery,
    OutboxEvent,
    PostgresOutboxPublisher,
    TenantTransaction
  }

  alias UokNext.PartyOnboardingFixtures
  alias UokNext.Repo

  defmodule RetryablePublisher do
    @behaviour UokNext.Kernel.OutboxPublisher

    @impl true
    def deliver(_event, _job, _options), do: {:error, "handoff_unavailable", :retryable}
  end

  defmodule PermanentPublisher do
    @behaviour UokNext.Kernel.OutboxPublisher

    @impl true
    def deliver(_event, _job, _options), do: {:error, "handoff_rejected", :permanent}
  end

  defmodule CrashBeforeHandoffPublisher do
    @behaviour UokNext.Kernel.OutboxPublisher

    @impl true
    def deliver(_event, _job, _options), do: raise("qualification crash before handoff")
  end

  defmodule CrashAfterHandoffPublisher do
    @behaviour UokNext.Kernel.OutboxPublisher

    @impl true
    def deliver(event, job, options) do
      {:ok, _delivery} = PostgresOutboxPublisher.deliver(event, job, options)
      raise "qualification crash after handoff"
    end
  end

  setup do
    context = PartyOnboardingFixtures.context()
    TenantTransaction.activate!(context.tenant_id)
    event = create_event(context)
    %{context: context, event: event, now: DateTime.add(event.available_at, 1, :second)}
  end

  test "schedules and publishes one event to an idempotent durable handoff", %{
    event: event,
    now: now
  } do
    assert {:ok, :published} = run_once(now)
    assert {:ok, :idle} = run_once(now)

    assert %{status: "completed", attempt_count: 1, last_error_code: nil} = job(event)

    assert %{status: "published", attempt_count: 1, published_at: published_at} =
             reload_event(event)

    assert %DateTime{} = published_at

    assert %{consumer: "kernel.local_handoff.v1", event_digest: digest} = delivery(event)
    assert byte_size(digest) == 32
  end

  test "reschedules a retryable failure with deterministic backoff", %{event: event, now: now} do
    assert {:ok, :retry_scheduled} =
             run_once(now, publisher: RetryablePublisher, base_backoff_ms: 100)

    retry_at = DateTime.add(now, 100, :millisecond)

    assert %{status: "scheduled", attempt_count: 1, run_at: ^retry_at} = job(event)

    assert %{status: "pending", attempt_count: 1, available_at: ^retry_at} =
             reload_event(event)

    assert {:ok, :idle} = run_once(DateTime.add(now, 99, :millisecond))
    assert {:ok, :published} = run_once(retry_at)
    assert %{status: "completed", attempt_count: 2} = job(event)
  end

  test "dead-letters an exhausted retry budget without a delivery receipt", %{
    event: event,
    now: now
  } do
    assert {:ok, :retry_scheduled} =
             run_once(now,
               publisher: RetryablePublisher,
               max_attempts: 2,
               base_backoff_ms: 100
             )

    retry_at = DateTime.add(now, 100, :millisecond)

    assert {:ok, :dead_letter} =
             run_once(retry_at, publisher: RetryablePublisher, max_attempts: 2)

    assert %{status: "dead_letter", attempt_count: 2, last_error_code: "handoff_unavailable"} =
             job(event)

    assert %{status: "dead_letter", attempt_count: 2, published_at: nil} =
             reload_event(event)

    assert is_nil(delivery(event))
  end

  test "dead-letters a permanent publisher rejection immediately", %{event: event, now: now} do
    assert {:ok, :dead_letter} = run_once(now, publisher: PermanentPublisher)

    assert %{status: "dead_letter", attempt_count: 1, last_error_code: "handoff_rejected"} =
             job(event)
  end

  test "forced row-level security hides an event from another tenant", %{
    context: context,
    event: event,
    now: now
  } do
    other_context = PartyOnboardingFixtures.context()
    Repo.query!("SET LOCAL ROLE pg_read_all_data", [], log: false)
    TenantTransaction.activate!(other_context.tenant_id)

    assert Repo.aggregate(OutboxEvent, :count) == 0
    assert Repo.aggregate(DurableJob, :count) == 0

    Repo.query!("RESET ROLE", [], log: false)
    TenantTransaction.activate!(context.tenant_id)
    assert {:ok, :published} = run_once(now)
    assert %{status: "completed"} = job(event)
  end

  test "restart recovery completes an expired lease when its handoff receipt exists", %{
    event: event,
    now: now
  } do
    assert_raise RuntimeError, "qualification crash after handoff", fn ->
      run_once(now, publisher: CrashAfterHandoffPublisher)
    end

    assert %{status: "running", attempt_count: 1} = running_job = job(event)
    assert %{status: "publishing", attempt_count: 1} = reload_event(event)
    assert %OutboxDelivery{} = delivery(event)
    expire_lease(running_job, now)

    assert {:ok, :idle} = run_once(now)
    assert %{status: "completed", attempt_count: 1} = job(event)
    assert %{status: "published", attempt_count: 1} = reload_event(event)
  end

  test "restart recovery reschedules an expired lease that has no receipt", %{
    event: event,
    now: now
  } do
    assert_raise RuntimeError, "qualification crash before handoff", fn ->
      run_once(now, publisher: CrashBeforeHandoffPublisher, base_backoff_ms: 100)
    end

    running_job = job(event)
    expire_lease(running_job, now)

    assert {:ok, :idle} = run_once(now, base_backoff_ms: 100)
    retry_at = DateTime.add(now, 100, :millisecond)
    assert %{status: "scheduled", attempt_count: 1, last_error_code: "lease_expired"} = job(event)

    assert {:ok, :published} = run_once(retry_at)
    assert %{status: "completed", attempt_count: 2} = job(event)
  end

  defp create_event(context) do
    aggregate_id = Ecto.UUID.generate()

    assert {:ok, _response, :executed} =
             CommandTransaction.execute(
               context,
               "kernel.test.emit",
               Ecto.UUID.generate(),
               %{aggregate_id: aggregate_id},
               fn ->
                 {:ok, %{aggregate_id: aggregate_id}, audit(aggregate_id),
                  [event_attrs(aggregate_id)]}
               end
             )

    Repo.one!(from outbox in OutboxEvent, where: outbox.aggregate_id == ^aggregate_id)
  end

  defp audit(aggregate_id) do
    %{
      action: "kernel.test.emit",
      resource_type: "qualification_record",
      resource_id: aggregate_id,
      reason: "Prove durable work behavior"
    }
  end

  defp event_attrs(aggregate_id) do
    %{
      name: "kernel.test.emitted",
      aggregate_type: "qualification_record",
      aggregate_id: aggregate_id,
      aggregate_version: 1,
      payload: %{qualification: true}
    }
  end

  defp run_once(now, overrides \\ []) do
    DurableWork.run_once(
      Keyword.merge(
        [
          repo: Repo,
          publisher: PostgresOutboxPublisher,
          now: now,
          batch_size: 5,
          lease_ms: 1_000,
          max_attempts: 5,
          base_backoff_ms: 100,
          max_backoff_ms: 1_000
        ],
        overrides
      )
    )
  end

  defp expire_lease(job, now) do
    Repo.update_all(
      from(candidate in DurableJob, where: candidate.id == ^job.id),
      set: [lease_expires_at: DateTime.add(now, -1, :millisecond)]
    )
  end

  defp job(event) do
    Repo.one(from job in DurableJob, where: job.outbox_event_id == ^event.id)
  end

  defp reload_event(event) do
    Repo.one!(from outbox in OutboxEvent, where: outbox.id == ^event.id)
  end

  defp delivery(event) do
    Repo.one(from receipt in OutboxDelivery, where: receipt.outbox_event_id == ^event.id)
  end
end
