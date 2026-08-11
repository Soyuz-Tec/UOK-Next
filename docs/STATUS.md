# Current Build Status

**Snapshot date:** 2026-08-11

**Canonical repository:** `https://github.com/Soyuz-Tec/UOK-Next`

**Visibility/default branch:** public, protected `main`

## One active focus

**Gate 1: complete the reproducible framework and kernel skeleton.**

## Verified foundation

- The accepted foundation is an Elixir 1.20.2, Erlang/OTP 28.4, Phoenix 1.8
  modular monolith targeting PostgreSQL 19. PG19 Beta 2 is digest-pinned for
  local/CI compatibility; production remains gated on PG19 GA/current minor.
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
  stale state, unavailable dependencies, schema-readiness failure paths, and a
  pre-migration PG19 major/prerelease compatibility gate.
- ADR-0007 now governs PostgreSQL as a complete data platform: deterministic
  UTF-8 cluster identity, checksums, SCRAM, explicit roles/default privileges,
  connection budgets, CA-authenticated TLS, tenant-aware foreign keys,
  migration safety, HA/fencing, WAL/PITR, restore drills, observability,
  vacuum/freeze, capacity, retention, and upgrades. Machine checks exercise
  the initial PG19 cluster and policy invariants.
- ADR-0008 now governs the UI delivery boundary. A responsive, accessible,
  module-neutral React 19.2 shell is implemented with one read-only readiness
  contract and no browser-owned business policy.
- Node 24 LTS, npm 11, Vite 8, native TypeScript 7, and the bounded TypeScript 6
  tooling API are exactly pinned. Format, lint, dual type checks, unit tests,
  advisory audit, architecture policy, and production build now run in CI.
- Content-hashed UI assets are built in a digest-pinned Node stage and copied
  into the same non-root Phoenix release. Phoenix applies a restrictive CSP,
  framing denial, no-store, referrer, MIME-sniffing, and browser-capability
  headers to the shell response.
- Local rendered proof covers 1440-by-1000 desktop and 390-by-844 phone
  viewports through the Phoenix delivery path: readiness reached `Kernel ready`,
  no horizontal overflow or console errors remained, and no business mutation
  control was exposed. Merged-SHA release qualification remains a Gate 1 gate.

## Gate 1 remaining work

1. Add a pinned local S3-compatible object-storage dependency and prove a
   bounded evidence-object contract without moving policy into the store.
2. Require the expanded CI and security gates on the protected branch, then
   close Gate 1 only after a clean candidate is rebuilt from the merged SHA.

## Explicitly not yet implemented

- Production identity/OIDC, session management, user-facing business APIs,
  business-module React UI, durable outbox delivery, jobs/workflows, object storage,
  external integrations, BI projections, or blockchain anchoring.
- The local two-replica qualifier is not a production topology. PostgreSQL 19
  is still a single local dependency and no backup/restore receipt exists.
- Production deployment is blocked on a selected platform, managed secrets,
  trusted TLS ingress, monitoring/alerting destinations, backup/restore,
  rollback, capacity, penetration, and disaster-recovery qualification.

## Next action

Add the Gate 1 object-storage development dependency and bounded evidence-object
contract while preserving PostgreSQL metadata authority, the selected Ecto
implementation, and the kernel boundaries.
