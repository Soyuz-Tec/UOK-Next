# ADR-0012: Provider-neutral connector receipts

**Status:** Accepted

**Date:** 2026-08-12

## Context

Gate 2 requires recoverable evidence for external side effects before any live
connector, scheduler, or autonomous plan may initiate them. A generic outbox
event alone does not prove which request a transport attempted, its deadline,
the attempt lineage, or how an outcome was classified. Storing raw remote
responses would also create an unbounded data, privacy, and retention surface.

The primitive must preserve module ownership: an external system remains the
source of truth for its records, while this application owns only its delivery
intent and reconciliation evidence.

## Decision

- `platform.integrations` owns connector receipts. Each row records the tenant,
  stable connector role, operation, delivery key, attempt number, request
  SHA-256, governed subject identity and version, timeout, server-derived
  deadline, actor, and optional previous receipt.
- Beginning an attempt commits the receipt, idempotent command result,
  append-only audit event, and outbox event in one command transaction. A
  tenant/connector/delivery/attempt tuple is unique.
- Reconciliation is a separate named command with optimistic concurrency.
  Outcomes are `succeeded`, `retryable_failure`, `permanent_failure`, or
  `timed_out`. Server time rejects an early timeout and rejects any non-timeout
  outcome after the deadline.
- A retry may reference only an exact prior `retryable_failure` or `timed_out`
  receipt. Connector role, operation, delivery key, request digest, subject,
  and subject version must match; the server derives the next attempt number.
- Response evidence is bounded to a SHA-256 digest, an optional printable
  reference, retry classification, and a mandatory reason. Raw response bodies
  are rejected and never persisted in command responses, audit metadata, or
  outbox payloads.
- Named permissions govern attempt, reconciliation, and read operations.
  Application queries are tenant-scoped and PostgreSQL forces row-level
  security. Missing and foreign-tenant receipts are indistinguishable.
- This increment does not send network traffic, resolve credentials, schedule
  retries, publish the outbox, define connectors, or copy external records.

## Consequences

Side-effect execution now has a deterministic, replay-safe evidence envelope
that can support later delivery and recovery workers without weakening record
ownership. Duplicate delivery attempts, stale reconciliation, lineage
substitution, foreign-tenant access, unsafe timeout claims, and raw response
storage fail closed. Live connector and dead-letter operations remain gated on
later verticals and operational evidence.

## Alternatives

- Treat the outbox row as the receipt: rejected because it lacks attempt and
  reconciled outcome semantics.
- Store complete request and response bodies: rejected because digests and
  governed references provide evidence without duplicating sensitive content.
- Let callers supply attempt numbers and timeout outcomes: rejected because
  retry ordering and deadlines are server-owned integrity decisions.
- Share an external system's database: rejected because it violates ownership,
  independent authorization, availability, and upgrade boundaries.

## Validation

- Integration tests prove atomic begin/reconcile commands, command replay and
  conflict, audit/outbox evidence, duplicate rejection, immutable retry
  lineage, retry-after-success rejection, timeout/recovery, stale state, and
  raw-response rejection.
- Negative tests prove named permissions, foreign-tenant hiding, and forced
  row-level security with unset or substituted tenant state.
- Database constraints enforce identifiers, digests, bounded timeout/retry
  values, lifecycle shape, unique attempts, same-tenant lineage, and positive
  versions. Architecture, code-discipline, migration, and security checks
  remain required before publication.
