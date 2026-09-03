\set ON_ERROR_STOP on

WITH target AS MATERIALIZED (
  SELECT job.id, job.outbox_event_id, job.attempt_count
  FROM kernel_durable_jobs AS job
  JOIN kernel_outbox_deliveries AS delivery
    ON delivery.tenant_id = job.tenant_id
   AND delivery.outbox_event_id = job.outbox_event_id
   AND delivery.consumer = 'kernel.local_handoff.v1'
  WHERE job.status = 'completed'
  ORDER BY job.completed_at DESC, job.id
  LIMIT 1
),
updated_event AS (
  UPDATE kernel_outbox_events AS event
  SET status = 'publishing', published_at = NULL, updated_at = clock_timestamp()
  FROM target
  WHERE event.id = target.outbox_event_id
  RETURNING event.id
),
updated_job AS (
  UPDATE kernel_durable_jobs AS job
  SET status = 'running',
      lease_token = '00000000-0000-4000-8000-000000000025'::uuid,
      lease_expires_at = clock_timestamp() - interval '1 second',
      completed_at = NULL,
      updated_at = clock_timestamp()
  FROM target, updated_event
  WHERE job.id = target.id
  RETURNING job.id, job.outbox_event_id, job.attempt_count
)
SELECT id::text || '|' || outbox_event_id::text || '|' || attempt_count::text
FROM updated_job;
