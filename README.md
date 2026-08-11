# UOK Next

UOK Next is a greenfield, evidence-first operating platform for multi-entity
commodity trade, supply-chain execution, CRM, ERP coordination, business
intelligence, collaboration, and governed AI-assisted operations.

The product is not a generic CRUD suite and it is not a blockchain application.
Its defining capability is to coordinate real business operations across
organizations while preserving explicit ownership, human decision authority,
evidence, policy, audit lineage, and recoverability.

## Current state

**Gate 1 is in progress.** The durable command kernel and first governed party
onboarding slice are implemented and locally qualified. The React shell and
object-storage dependency remain before Gate 1 can close. No production
business capability is claimed.

The target stack is:

- Elixir, Phoenix, Erlang/OTP, and PostgreSQL for the product-neutral kernel
  and business modular monolith;
- explicit Elixir/Ecto application services; the completed bounded spike did
  not justify adopting Ash in the production dependency graph;
- React and TypeScript for internal, partner, public, and field/PWA surfaces;
- Rust for collaboration and analytical engines;
- Python for OCR, document intelligence, and AI workers;
- K-Comms, K-Board, Odoo, and optional blockchain anchoring behind explicit
  authority-preserving integration contracts.

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

Machine-readable architecture authority is in
[`config/module_catalog.json`](config/module_catalog.json).

## Verify the foundation

From PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify_foundation.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify_code_discipline.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify_architecture_boundaries.ps1
```

This verifies that required authority documents exist, module and external
system identifiers are unique, and no record type has more than one declared
system of record.

Install or activate the pinned Windows Elixir/Erlang toolchain with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup_elixir_toolchain.ps1 -PersistUserPath
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup_framework_tools.ps1
```

Start the pinned local PostgreSQL dependency and run the application checks:

```powershell
.\scripts\start_local_postgres.ps1
mix setup
mix quality
```

The local dependency binds PostgreSQL to `127.0.0.1:15432`. Its startup script
generates and rotates a clone-local owner credential under
`%LOCALAPPDATA%\UOK-Next\credentials\<clone-hash>` outside the repository and
OneDrive. It replaces inherited filesystem permissions with a fail-closed ACL
for the current Windows user, SYSTEM, and Administrators; there is no committed
password. Copy `.env.example` to `.env` only when local overrides are required.
Production credentials must come from a deployment secret store.

From a clean committed revision, build and deploy the complete two-replica
local qualification topology with:

```powershell
.\scripts\deploy_local_qualification.ps1
```

The command generates ephemeral secrets, reconciles a least-privileged runtime
database role, migrates through the owner role, compiles the exact Git revision
into an immutable release, starts two forced-recreated replicas behind HAProxy,
verifies each replica's image and release identity plus authenticated metrics,
deliberately poisons and repairs persistent role state before startup, and
proves single-replica failover. It binds only to loopback and is not a
production deployment.
