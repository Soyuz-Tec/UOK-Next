# ADR-0025: PostgreSQL durable outbox handoff

**Status:** Accepted

**Date:** 2026-09-03

## Context

Gate 3 has transactional outbox records, but no process delivers them. A
process-local timer or fire-and-forget message would lose work on restart, and
letting the application database role update delivery state would weaken the
role boundary already defined in the database architecture. Starting a live
connector would also outrun the existing credential, authorization,
reconciliation, and production-platform gates.

The first durable-work increment therefore needs to prove scheduling, bounded
claiming, retry, dead-letter, observability, and restart recovery without
claiming that an external side effect occurred.

## Decision

- Each pending kernel outbox event is assigned one PostgreSQL-backed
  `kernel.outbox.publish` job. The event remains the immutable payload source;
  the job stores only scheduling, lease, attempt, and bounded failure state.
- A separately configured `uok_outbox` repository owns the cross-tenant worker
  algorithm. Its database role has no business-command authority and receives
  only the table privileges needed to select and update outbox events, manage
  their jobs, and append delivery receipts.
- Competing workers claim due jobs with `FOR UPDATE SKIP LOCKED`, a random lease
  token, and a bounded lease expiry. A process may complete or fail only the
  exact lease it owns.
- The only publisher in this increment is `kernel.local_handoff.v1`. It writes
  an idempotent PostgreSQL receipt containing the outbox identity and a
  deterministic event digest, but no copied event payload. This is a durable
  internal handoff, not an external connector success or business effect.
- A retryable publisher failure reschedules the same job with deterministic
  exponential backoff. A permanent failure, or exhaustion of the bounded
  attempt budget, moves both job and event to `dead_letter`. Error state is a
  bounded code; raw exception, response, credential, and payload data are not
  persisted.
- An expired lease is recovered from PostgreSQL. If the idempotent handoff
  receipt already exists, recovery completes the job without another delivery
  attempt. Otherwise it reschedules within the remaining attempt budget or
  dead-letters the exhausted job.
- Durable-work execution emits bounded Prometheus outcomes for execution and
  lease recovery. Readiness includes the worker repository when durable work is
  enabled. Production and local-qualification releases enable the worker and
  require its separate database URL.
- This increment does not resolve connector credentials, send network traffic,
  schedule connector retries, consume business events, mutate module-owned
  state, or create a second Gate 3 proving operation.

## Consequences

Committed events now reach a restart-safe, idempotent local handoff with
observable job state. Multiple application replicas may run workers without
claiming the same due job. A receipt written immediately before a process loss
can be reconciled after lease expiry without duplicate handoff.

The local receipt is deliberately not a consumer acknowledgement. Retention,
consumer registration, payload access, live connector transport, credentials,
connector-specific retry policy, operator redrive, and production alerting
remain later decisions. Dead-letter state is visible through existing bounded
delivery-lineage reporting and metrics, but no redrive command is introduced.

## Alternatives considered

- Mark an event published after an in-memory or PubSub send: rejected because
  neither provides a durable consumer receipt across process loss.
- Run delivery through `uok_app`: rejected because application replicas must
  not gain cross-tenant update authority over the outbox.
- Adopt a general job library now: deferred because the first job kind has a
  narrow schema and no measured need for a broader dependency or job DSL.
- Start a provider connector as the first publisher: rejected because delivery
  credentials, current authorization, receipts, and reconciliation require a
  separate bounded vertical.

## Validation

- Integration tests prove scheduling, single-claim completion, idempotent
  receipts, retry delay, attempt exhaustion, permanent dead-letter, and both
  receipt-present and receipt-absent expired-lease recovery.
- Database constraints and forced row-level security prove bounded lifecycle
  shape, tenant-bound references, and an exact cross-tenant worker identity.
- Role qualification proves `uok_outbox` has no membership, unsafe attribute,
  sequence access, or table privilege beyond the durable-work tables.
- Runtime qualification proves both replicas use the exact image, drain the
  committed Gate 3 outbox, expose durable-work metrics, and recover an expired
  receipt-present lease after an application restart.
