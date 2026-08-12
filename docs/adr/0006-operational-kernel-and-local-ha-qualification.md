# ADR-0006: Operational kernel and local HA qualification

**Status:** Accepted

**Date:** 2026-08-11

**Amended:** 2026-08-12

## Context

The first business slice needs durable command semantics and production-shaped
runtime evidence before feature breadth. A running process or a successful
HTTP request alone does not prove atomic mutation, replay safety, auditability,
release identity, dependency readiness, or replica failover. The repository
also does not yet define a trusted production ingress or backup target.

## Decision

- Every mutating business operation crosses `CommandTransaction`, which binds
  tenant context, a bounded idempotency key, canonical payload identity,
  business mutation, append-only audit, outbox publication, and the completed
  command receipt in one PostgreSQL transaction.
- Liveness proves only that the BEAM can answer. Readiness and startup require
  the database and required migration version, but a serialized, one-second
  cache and strict admission limit bound unauthenticated probe work. Load
  balancers use readiness; process supervisors use liveness.
- Prometheus metrics are available only with a constant-time checked bearer
  token. Health responses expose no secrets or dependency error details.
- Releases are built in a multi-stage, non-root container from digest-pinned
  bases and hash-verified Elixir, Hex, and Rebar artifacts. Runtime containers
  are read-only, drop Linux capabilities, and use bounded resources. The full
  source revision is compiled into the release and cannot be replaced by a
  runtime environment variable.
- Local qualification runs two identical application replicas behind HAProxy
  with one migration job and PostgreSQL. It is a development qualification
  target, not a production topology or a substitute for regional resilience.
  Before either replica starts, it seeds and then proves reconciliation of
  unsafe persistent role attributes, settings, grants, and memberships. It
  also establishes a live session under the stale authorization, blocks new
  non-superuser connections, terminates existing client sessions, and proves
  that the stale session cannot survive reconciliation.
- The local qualifier must also serve the read-only browser shell through its
  loopback proxy. Plaintext delivery is excluded from the HTTPS redirect only
  when the explicit local profile, loopback request host, private container
  binding, isolated database host, and isolated object-store transport all
  match. Any missing invariant fails closed, and production never activates
  this exception.
- Until a production ingress ADR proves TLS termination, header sanitization,
  network isolation, and source identity, the default production endpoint
  remains loopback-only and PostgreSQL TLS remains mandatory.

## Initial service objectives

The local qualifier must demonstrate consecutive successful readiness and
release-identity requests after HAProxy's bounded failure-detection window when
one of two healthy application replicas is deliberately stopped. Commands must
remain atomic under database errors and replay the same completed result for
the same tenant, key, command, and payload.

The same qualifier must follow the shell route through the proxy to an HTTP 200
HTML response. Production configuration tests must prove that the local
exception is inactive and that spoofed host and forwarded-protocol headers do
not bypass the HTTPS redirect.

Provisional production objectives are 99.9% monthly API availability, a
15-minute recovery point objective, and a 60-minute recovery time objective.
These are hypotheses until Gate 7 proves alerting, backups, restore receipts,
capacity, dependency failure, and rollback on the selected production
platform.

## Consequences

The app gains a small operational kernel and a repeatable local failover test
without prematurely adopting distributed consensus or microservices. The
database is still a single local dependency, object storage is not present,
and no production availability claim is made. Production deployment remains
blocked on an approved platform topology, managed secrets, trusted TLS ingress,
backup/restore evidence, monitoring destinations, and rollback qualification.

## Alternatives considered

- In-memory idempotency or audit after commit: rejected because crashes create
  ambiguous outcomes and missing evidence.
- Kubernetes or BEAM clustering in Gate 1: deferred because neither addresses
  the current single-database recovery gap and no measured scaling need exists.
- Exposing plaintext production HTTP behind assumed proxy headers: rejected
  until the proxy trust boundary is explicitly designed and tested.

## Validation

- contract and negative tests for tenant scope, authorization, optimistic
  concurrency, idempotent replay/conflict, audit, and outbox behavior;
- production release compilation and a digest-addressable local image;
- two healthy replicas through HAProxy, authenticated metrics, immutable image
  and per-replica release-identity verification, and a live single-replica
  failover request;
- loopback browser-shell proof plus positive local-profile and negative
  non-local/production transport tests;
- architecture, static analysis, dependency audit, container scan, and a
  repository-wide Codex Security assessment before publication.
