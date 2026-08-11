# Current Build Status

**Snapshot date:** 2026-08-11

**Canonical repository:** `https://github.com/Soyuz-Tec/UOK-Next`

**Visibility/default branch:** public, protected `main`

## One active focus

**Gate 1: complete the reproducible framework and kernel skeleton.**

## Verified foundation

- The accepted foundation is an Elixir 1.20.2, Erlang/OTP 28.4, Phoenix 1.8
  modular monolith backed by PostgreSQL 18.4.
- Toolchain archives, framework bootstrap artifacts, GitHub Actions, base
  images, PostgreSQL, and HAProxy are pinned to repository-owned hashes or
  immutable digests and fail closed on identity mismatch.
- Architecture, module ownership, code discipline, production transport
  controls, and release decisions are repository-owned and machine-checked.
- `main` is protected; Foundation CI, review resolution, linear history, and
  administrative enforcement remain delivery gates.

## Implemented in the current Gate 1 increment

- Equivalent explicit Ecto and Ash party-onboarding candidates were built
  against one contract and measured. ADR-0002 selects explicit Elixir/Ecto;
  the Ash candidate and all Ash dependencies were removed.
- `master.parties` now has a narrow governed onboarding slice: draft creation,
  evidence submission, approval/hold decisions, tenant-safe reads, named
  permissions, mandatory reasons, optimistic concurrency, and stable identity.
- Mutations atomically persist business state, an idempotent command receipt,
  append-only audit evidence, and versioned outbox events.
- PostgreSQL forces row-level tenant isolation. Runtime replicas use a dedicated
  non-superuser, non-`BYPASSRLS` role and activate a validated tenant only for
  the current database transaction; migrations use a separate owner role.
- Liveness, admission-limited cached readiness/startup, immutable release
  identity, bounded database timeouts, authenticated Prometheus metrics, and
  command telemetry are implemented.
- The release builds in a non-root, read-only container with dropped
  capabilities and bounded CPU, memory, process, and temporary-file resources.
- The supported local qualifier runs one migration job and two identical app
  replicas behind HAProxy. Readiness, release identity, metrics authorization,
  reconciled least-privileged database access, DNS refresh, per-replica image
  identity, and single-replica failover have been exercised on Podman.
- Application tests include authorization, input, tenant mismatch, database
  row-level isolation, atomic audit/outbox/receipt creation, replay conflict,
  stale state, unavailable dependencies, and schema-readiness failure paths.

## Gate 1 remaining work

1. Add the minimal React/TypeScript shell and its formatter, lint, type, test,
   and reproducible production build.
2. Add a pinned local S3-compatible object-storage dependency and prove a
   bounded evidence-object contract without moving policy into the store.
3. Require the expanded CI and security gates on the protected branch, then
   close Gate 1 only after a clean candidate is rebuilt from the merged SHA.

## Explicitly not yet implemented

- Production identity/OIDC, session management, user-facing business APIs, the
  operational React UI, durable outbox delivery, jobs/workflows, object storage,
  external integrations, BI projections, or blockchain anchoring.
- The local two-replica qualifier is not a production topology. PostgreSQL is
  still a single local dependency and no backup/restore receipt exists.
- Production deployment is blocked on a selected platform, managed secrets,
  trusted TLS ingress, monitoring/alerting destinations, backup/restore,
  rollback, capacity, penetration, and disaster-recovery qualification.

## Next action

Complete the Gate 1 React/TypeScript shell and object-storage development
dependency while preserving the selected Ecto implementation and kernel
boundaries.
