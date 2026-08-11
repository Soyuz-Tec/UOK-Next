# ADR-0002: Selective Ash Adoption Requires a Spike

**Status:** Accepted

**Date:** 2026-08-11

## Context

Ash provides resources, named actions, policies, multitenancy, APIs, and
extensions that closely match the target business model. It also introduces a
substantial abstraction and learning boundary. The kernel must not become
opaque or force infrastructure concepts into resources.

## Decision

Use explicit Elixir application services, pure domain decisions, application-
owned persistence ports, and Ecto adapters for the kernel and initial business
modules. Do not adopt Ash in the production dependency graph at Gate 1.

Ash may be reconsidered for a future bounded module only when measured evidence
shows that its resource and policy model removes more complexity than its
runtime, compile-time, migration, and debugging surface adds.

## Evidence

The same party-onboarding lifecycle was implemented through explicit Ecto and
AshPostgres candidates. Both passed shared contract and HTTP tests covering:

- named create, evidence, approval, and HOLD commands;
- permission denial and tenant mismatch;
- idempotent replay and key-conflict rejection;
- optimistic concurrency and stale-state rejection;
- transactional state, receipt, audit, and outbox persistence;
- equivalent versioned JSON response and error shapes.

A rollback-only local PostgreSQL measurement ran 30 complete create, evidence,
and approval lifecycles per implementation after compilation. It is a bounded
development comparison, not a capacity or production benchmark.

| Candidate | p50 | p95 | Mean | Adapter source |
|---|---:|---:|---:|---:|
| Explicit Ecto | 7.987 ms | 13.312 ms | 10.550 ms | 176 lines / 3 files |
| AshPostgres | 7.987 ms | 12.390 ms | 15.561 ms | 226 lines / 5 files |

The shared product-neutral kernel, domain, policy, and application contract was
818 lines across 10 files and was excluded from both adapter counts.

Ash did not produce a material correctness or latency advantage in this slice.
Its policy verifier required an additional SAT-solver dependency. Its full
atomic update path required optional Ash database functions; without them the
candidate needed an explicit non-atomic action setting while retaining
optimistic locking. Nested transaction notifications and framework errors also
required adapter-specific handling to avoid missed notifications and internal
detail disclosure.

Explicit Ecto kept the transaction, row lock, optimistic version, SQL
constraints, error mapping, and rollback behavior visible at the owning
boundary while producing the lower mean latency and smaller adapter surface.

## Consequences

- Ash, AshPostgres, AshPhoenix, and the spike-only SAT solver are removed from
  the active dependency graph.
- Shared fixtures and behavioral contracts are retained against the selected
  implementation.
- Module manifests, command receipts, policy decisions, audit, events, outbox,
  and operational contracts remain explicit product concepts.
- This decision does not prohibit a later evidence-backed Ash evaluation, but
  framework adoption is no longer part of Gate 1.
