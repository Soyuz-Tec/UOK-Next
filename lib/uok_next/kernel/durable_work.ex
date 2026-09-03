defmodule UokNext.Kernel.DurableWork do
  @moduledoc """
  Claims and executes the bounded PostgreSQL outbox-publishing job.

  All scheduling, leases, retries, and terminal state are durable. Publisher
  implementations cannot complete or fail a lease that they do not own.
  """

  import Ecto.Query

  alias UokNext.Kernel.{DurableJob, OutboxDelivery, OutboxEvent, PostgresOutboxPublisher}

  @job_kind "kernel.outbox.publish"
  @schedule_batch_size 100

  @type outcome :: :idle | :published | :retry_scheduled | :dead_letter

  @spec run_once(keyword()) :: {:ok, outcome()} | {:error, atom()}
  def run_once(overrides \\ []) do
    options = options(overrides)
    started_at = System.monotonic_time()

    try do
      result = execute_once(options)
      emit_execution(result, started_at)
      result
    rescue
      error ->
        emit_execution({:error, :crashed}, started_at)
        reraise error, __STACKTRACE__
    end
  end

  @spec drain(keyword()) :: {:ok, [outcome()]} | {:error, atom()}
  def drain(overrides \\ []) do
    options = options(overrides)

    Enum.reduce_while(1..options[:batch_size], {:ok, []}, fn _index, {:ok, outcomes} ->
      case run_once(options) do
        {:ok, :idle} -> {:halt, {:ok, Enum.reverse(outcomes)}}
        {:ok, outcome} -> {:cont, {:ok, [outcome | outcomes]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp execute_once(options) do
    repo = options[:repo]
    now = now(options)

    schedule_pending(repo, now, options[:max_attempts])
    recover_one(repo, now, options)

    case claim_one(repo, now, options[:lease_ms]) do
      nil ->
        {:ok, :idle}

      {job, event} ->
        publish_claim(job, event, now, options)
    end
  end

  defp schedule_pending(repo, now, max_attempts) do
    events =
      repo.all(
        from event in OutboxEvent,
          left_join: job in DurableJob,
          on:
            job.tenant_id == event.tenant_id and
              job.outbox_event_id == event.id,
          where: event.status == "pending" and is_nil(job.id),
          order_by: [asc: event.available_at, asc: event.id],
          limit: @schedule_batch_size,
          select: %{id: event.id, tenant_id: event.tenant_id, available_at: event.available_at}
      )

    rows =
      Enum.map(events, fn event ->
        %{
          id: Ecto.UUID.generate(),
          tenant_id: event.tenant_id,
          job_kind: @job_kind,
          outbox_event_id: event.id,
          status: "scheduled",
          run_at: event.available_at,
          attempt_count: 0,
          max_attempts: max_attempts,
          inserted_at: now,
          updated_at: now
        }
      end)

    repo.insert_all(DurableJob, rows,
      on_conflict: :nothing,
      conflict_target: [:tenant_id, :outbox_event_id]
    )
  end

  defp recover_one(repo, now, options) do
    result =
      repo.transaction(fn ->
        case expired_job(repo, now) do
          nil -> :none
          job -> recover_job(repo, job, now, options)
        end
      end)
      |> unwrap_transaction()

    if result != :none, do: emit_recovery(result)
    result
  end

  defp expired_job(repo, now) do
    repo.one(
      from job in DurableJob,
        where: job.status == "running" and job.lease_expires_at <= ^now,
        order_by: [asc: job.lease_expires_at, asc: job.id],
        limit: 1,
        lock: "FOR UPDATE SKIP LOCKED"
    )
  end

  defp recover_job(repo, job, now, options) do
    event = lock_event!(repo, job)

    case existing_delivery(repo, event) do
      nil -> recover_without_delivery(repo, job, event, now, options)
      delivery -> recover_with_delivery(repo, job, event, delivery, now)
    end
  end

  defp recover_with_delivery(repo, job, event, delivery, now) do
    expected_digest = PostgresOutboxPublisher.digest(event)

    if delivery.event_digest == expected_digest do
      finish_job(repo, job, event, now)
      :completed
    else
      dead_letter(repo, job, event, "delivery_conflict", now)
      :dead_letter
    end
  end

  defp recover_without_delivery(repo, job, event, now, options) do
    if job.attempt_count >= job.max_attempts do
      dead_letter(repo, job, event, "lease_expired", now)
      :dead_letter
    else
      retry_at = DateTime.add(now, retry_delay(job.attempt_count, options), :millisecond)
      reschedule(repo, job, event, "lease_expired", retry_at, now)
      :rescheduled
    end
  end

  defp claim_one(repo, now, lease_ms) do
    repo.transaction(fn ->
      case due_job(repo, now) do
        nil ->
          nil

        job ->
          claim_job(repo, job, now, lease_ms)
      end
    end)
    |> unwrap_transaction()
  end

  defp claim_job(repo, job, now, lease_ms) do
    event = lock_event!(repo, job)

    if event.status != "pending" do
      repo.rollback(:inconsistent_event_state)
    end

    lease_token = Ecto.UUID.generate()
    lease_expires_at = DateTime.add(now, lease_ms, :millisecond)
    attempt_count = job.attempt_count + 1

    update_job_claim!(repo, job, lease_token, lease_expires_at, attempt_count, now)
    update_event_claim!(repo, event, attempt_count, now)

    {%{
       job
       | status: "running",
         lease_token: lease_token,
         lease_expires_at: lease_expires_at,
         attempt_count: attempt_count,
         updated_at: now
     }, %{event | status: "publishing", attempt_count: attempt_count, updated_at: now}}
  end

  defp due_job(repo, now) do
    repo.one(
      from job in DurableJob,
        where:
          job.status == "scheduled" and job.run_at <= ^now and
            job.attempt_count < job.max_attempts,
        order_by: [asc: job.run_at, asc: job.id],
        limit: 1,
        lock: "FOR UPDATE SKIP LOCKED"
    )
  end

  defp publish_claim(job, event, now, options) do
    publisher_options = [repo: options[:repo], now: now]

    case options[:publisher].deliver(event, job, publisher_options) do
      {:ok, delivery} ->
        complete_claim(options[:repo], job, event, delivery, now)

      {:error, error_code, failure_class}
      when is_binary(error_code) and failure_class in [:retryable, :permanent] ->
        fail_claim(options[:repo], job, event, error_code, failure_class, now, options)

      _invalid ->
        fail_claim(
          options[:repo],
          job,
          event,
          "publisher_contract_violation",
          :permanent,
          now,
          options
        )
    end
  end

  defp complete_claim(repo, job, event, delivery, now) do
    repo.transaction(fn ->
      locked_job = lock_owned_job(repo, job)

      if valid_delivery?(repo, event, delivery) do
        finish_job(repo, locked_job, lock_event!(repo, locked_job), now)
        :published
      else
        repo.rollback(:delivery_receipt_missing)
      end
    end)
    |> case do
      {:ok, outcome} -> {:ok, outcome}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fail_claim(repo, job, _event, error_code, failure_class, now, options) do
    repo.transaction(fn ->
      locked_job = lock_owned_job(repo, job)
      locked_event = lock_event!(repo, locked_job)
      code = bounded_error_code(error_code)

      if failure_class == :retryable and locked_job.attempt_count < locked_job.max_attempts do
        retry_at =
          DateTime.add(now, retry_delay(locked_job.attempt_count, options), :millisecond)

        reschedule(repo, locked_job, locked_event, code, retry_at, now)
        :retry_scheduled
      else
        dead_letter(repo, locked_job, locked_event, code, now)
        :dead_letter
      end
    end)
    |> case do
      {:ok, outcome} -> {:ok, outcome}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lock_owned_job(repo, job) do
    case repo.one(
           from candidate in DurableJob,
             where:
               candidate.id == ^job.id and candidate.status == "running" and
                 candidate.lease_token == ^job.lease_token,
             lock: "FOR UPDATE"
         ) do
      nil -> repo.rollback(:lease_lost)
      locked_job -> locked_job
    end
  end

  defp lock_event!(repo, job) do
    repo.one!(
      from event in OutboxEvent,
        where: event.tenant_id == ^job.tenant_id and event.id == ^job.outbox_event_id,
        lock: "FOR UPDATE"
    )
  end

  defp existing_delivery(repo, event) do
    consumer = PostgresOutboxPublisher.consumer()

    repo.one(
      from delivery in OutboxDelivery,
        where:
          delivery.tenant_id == ^event.tenant_id and
            delivery.outbox_event_id == ^event.id and
            delivery.consumer == ^consumer
    )
  end

  defp valid_delivery?(repo, event, delivery) do
    expected_digest = PostgresOutboxPublisher.digest(event)
    consumer = PostgresOutboxPublisher.consumer()

    repo.exists?(
      from receipt in OutboxDelivery,
        where:
          receipt.id == ^delivery.id and receipt.tenant_id == ^event.tenant_id and
            receipt.outbox_event_id == ^event.id and
            receipt.consumer == ^consumer and
            receipt.event_digest == ^expected_digest
    )
  end

  defp update_job_claim!(repo, job, lease_token, lease_expires_at, attempt_count, now) do
    {1, nil} =
      repo.update_all(
        from(candidate in DurableJob, where: candidate.id == ^job.id),
        set: [
          status: "running",
          lease_token: lease_token,
          lease_expires_at: lease_expires_at,
          attempt_count: attempt_count,
          last_error_code: nil,
          updated_at: now
        ]
      )
  end

  defp update_event_claim!(repo, event, attempt_count, now) do
    {1, nil} =
      repo.update_all(
        from(candidate in OutboxEvent, where: candidate.id == ^event.id),
        set: [status: "publishing", attempt_count: attempt_count, updated_at: now]
      )
  end

  defp finish_job(repo, job, event, now) do
    {1, nil} =
      repo.update_all(
        from(candidate in DurableJob, where: candidate.id == ^job.id),
        set: [
          status: "completed",
          lease_token: nil,
          lease_expires_at: nil,
          completed_at: now,
          last_error_code: nil,
          updated_at: now
        ]
      )

    {1, nil} =
      repo.update_all(
        from(candidate in OutboxEvent, where: candidate.id == ^event.id),
        set: [status: "published", published_at: now, updated_at: now]
      )
  end

  defp reschedule(repo, job, event, error_code, retry_at, now) do
    {1, nil} =
      repo.update_all(
        from(candidate in DurableJob, where: candidate.id == ^job.id),
        set: [
          status: "scheduled",
          run_at: retry_at,
          lease_token: nil,
          lease_expires_at: nil,
          completed_at: nil,
          last_error_code: error_code,
          updated_at: now
        ]
      )

    {1, nil} =
      repo.update_all(
        from(candidate in OutboxEvent, where: candidate.id == ^event.id),
        set: [status: "pending", available_at: retry_at, published_at: nil, updated_at: now]
      )
  end

  defp dead_letter(repo, job, event, error_code, now) do
    {1, nil} =
      repo.update_all(
        from(candidate in DurableJob, where: candidate.id == ^job.id),
        set: [
          status: "dead_letter",
          run_at: now,
          lease_token: nil,
          lease_expires_at: nil,
          completed_at: nil,
          last_error_code: error_code,
          updated_at: now
        ]
      )

    {1, nil} =
      repo.update_all(
        from(candidate in OutboxEvent, where: candidate.id == ^event.id),
        set: [status: "dead_letter", published_at: nil, updated_at: now]
      )
  end

  defp retry_delay(attempt_count, options) do
    multiplier = Integer.pow(2, min(max(attempt_count - 1, 0), 9))
    min(options[:base_backoff_ms] * multiplier, options[:max_backoff_ms])
  end

  defp bounded_error_code(error_code) do
    if Regex.match?(~r/\A[a-z][a-z0-9_]{2,63}\z/, error_code) do
      error_code
    else
      "publisher_failure"
    end
  end

  defp options(overrides) do
    :uok_next
    |> Application.fetch_env!(:durable_work)
    |> Keyword.merge(overrides)
  end

  defp now(options), do: Keyword.get_lazy(options, :now, &DateTime.utc_now/0)

  defp unwrap_transaction({:ok, result}), do: result

  defp unwrap_transaction({:error, reason}),
    do: raise("durable work transaction failed: #{inspect(reason)}")

  defp emit_execution(result, started_at) do
    :telemetry.execute(
      [:uok_next, :durable_work, :stop],
      %{duration: System.monotonic_time() - started_at},
      %{job: @job_kind, outcome: execution_outcome(result)}
    )
  end

  defp execution_outcome({:ok, outcome}), do: Atom.to_string(outcome)
  defp execution_outcome({:error, outcome}), do: Atom.to_string(outcome)

  defp emit_recovery(outcome) do
    :telemetry.execute(
      [:uok_next, :durable_work, :recovery],
      %{count: 1},
      %{job: @job_kind, outcome: Atom.to_string(outcome)}
    )
  end
end
