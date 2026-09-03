# UOK Next

UOK Next is a greenfield, evidence-first operating platform for multi-entity
commodity trade, supply-chain execution, CRM, ERP coordination, business
intelligence, collaboration, and governed AI-assisted operations.

The product is not a generic CRUD suite and it is not a blockchain application.
Its defining capability is to coordinate real business operations across
organizations while preserving explicit ownership, human decision authority,
evidence, policy, audit lineage, and recoverability.

## Current state

**Gates 1 and 2 are qualified and Gate 3 is active.** The first proving
operation now reaches attributable party onboarding, sourcing, deterministic
quote comparison, an internal commitment proposal, shipment-readiness GO/HOLD,
and a governed operational report through the real API, PostgreSQL, object
storage, and React UI. Protected delivery, exact-revision two-replica local
qualification, role-bounded regular-user access, failover, and rendered desktop
and mobile proof have passed. The PostgreSQL durable-work candidate now adds a
separately credentialed outbox worker, scheduled jobs, idempotent local handoff,
bounded retry/dead-letter, metrics, and restart recovery. Protected delivery
and exact merged-revision requalification remain required; no production
capability or topology is claimed.

The target stack is:

- Elixir, Phoenix, Erlang/OTP, and PostgreSQL 19 for the product-neutral kernel
  and business modular monolith;
- explicit Elixir/Ecto application services; the completed bounded spike did
  not justify adopting Ash in the production dependency graph;
- React and TypeScript for internal, partner, public, and field/PWA surfaces;
- bounded specialist runtimes for collaboration, document intelligence, and
  analytical execution;
- external communications, collaborative-canvas, selected back-office, and
  optional evidence-anchor systems behind explicit authority-preserving
  integration contracts.

## Start here

Read these files in order before making a material change:

1. [Product charter](docs/PRODUCT_CHARTER.md)
2. [Architecture](docs/ARCHITECTURE.md)
3. [Modular monolith contract](docs/MODULAR_MONOLITH_CONTRACT.md)
4. [Engineering standards](docs/ENGINEERING_STANDARDS.md)
5. [Module ownership](docs/MODULE_OWNERSHIP.md)
6. [Current status](docs/STATUS.md)
7. [Roadmap](docs/ROADMAP.md)
8. [Development continuity](docs/DEVELOPMENT_CONTINUITY.md)
9. [Decision log](docs/DECISION_LOG.md)
10. [Gate 1 framework spike](docs/GATE_1_FRAMEWORK_SPIKE.md)
11. [PostgreSQL 19 data-platform architecture](docs/DATABASE_ARCHITECTURE.md)

Machine-readable architecture authority is in
[`config/module_catalog.json`](config/module_catalog.json).
External-system naming authority is in
[`config/external_identity_policy.json`](config/external_identity_policy.json).

## Verify the foundation

From PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify_foundation.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\test\architecture\external_identity_policy_test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify_code_discipline.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify_architecture_boundaries.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify_database_policy.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify_object_storage_policy.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify_web_foundation.ps1
```

This verifies that required authority documents exist, external systems use
approved role-based identifiers, module and external-system identifiers are
unique, and no record type has more than one declared system of record.

Install or activate the pinned Windows Elixir/Erlang toolchain with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup_elixir_toolchain.ps1 -PersistUserPath
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup_framework_tools.ps1
```

Start the pinned local PostgreSQL dependency and run the application checks:

```powershell
.\scripts\start_local_postgres.ps1
npm ci --prefix web --ignore-scripts --no-audit --no-fund
npm run quality --prefix web
mix setup
mix quality
```

The web build writes ignored, content-hashed assets to
`priv/static/uok-ui`. Phoenix serves the shell and same-origin API from one
release; browser code is presentation-only and does not own authorization,
tenant, approval, audit, or business-transition policy.

For an alternate loopback Phoenix development port, set `UOK_API_ORIGIN` for
the Vite process to an `http://127.0.0.1:<port>` or
`http://localhost:<port>` origin. Non-loopback and non-HTTP proxy targets fail
closed.

The local dependencies bind the digest-pinned PostgreSQL 19 compatibility
build to `127.0.0.1:15432` and the digest-pinned S3-compatible qualifier to
`127.0.0.1:18333`. The PostgreSQL startup script
generates and rotates a clone-local owner credential under
`%LOCALAPPDATA%\UOK-Next\credentials\<clone-hash>` outside the repository and
OneDrive. It replaces inherited filesystem permissions with a fail-closed ACL
for the current Windows user, SYSTEM, and Administrators; there is no committed
password. Copy `.env.example` to `.env` only when local overrides are required.
Production credentials must come from a deployment secret store. PG19 Beta 2
is qualification-only; production promotion requires PG19 GA/current minor.

From a clean committed revision, build and deploy the complete two-replica
local qualification topology with:

```powershell
.\scripts\deploy_local_qualification.ps1
```

The command generates ephemeral database, metrics, application, and object-
store secrets, reconciles a least-privileged runtime
database role, migrates through the owner role, compiles the exact Git revision
into an immutable release, starts two forced-recreated replicas behind HAProxy,
verifies a bounded content-addressed object put/collision-rejection/read/delete plus each replica's
image and release identity and authenticated metrics,
deliberately poisons and repairs persistent role state, terminates a live stale
authorized database session before startup, and proves single-replica failover.
It binds only to loopback and is not a production deployment.
