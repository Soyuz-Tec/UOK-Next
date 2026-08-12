# UOK Next Working Agreement

These instructions apply to the entire repository.

## Establish authority before work

Before changing code or architecture, read:

1. `docs/PRODUCT_CHARTER.md`
2. `docs/ARCHITECTURE.md`
3. `docs/MODULAR_MONOLITH_CONTRACT.md`
4. `docs/ENGINEERING_STANDARDS.md`
5. `docs/MODULE_OWNERSHIP.md`
6. `docs/STATUS.md`
7. `docs/ROADMAP.md`
8. Relevant ADRs under `docs/adr/`

Treat repository files, tests, Git/GitHub state, and runtime evidence as more
authoritative than conversation history or model memory.

## Preserve focus

- There must be exactly one active delivery focus in `docs/STATUS.md`.
- Do not begin a new bounded context while the current focus has an unmet exit
  criterion unless an ADR explicitly changes the sequence.
- Each change must identify the product outcome, owning module, affected
  commands/events, tests, operational risk, and rollback path.
- Update `docs/STATUS.md` whenever verified capability, blockers, or the next
  action changes.
- Record material architecture, data, security, integration, framework, and
  deployment decisions as ADRs. Do not leave durable decisions only in chat.

## Protect architectural boundaries

- The kernel is product-neutral. Commodity-specific behavior belongs to
  business modules.
- Every business record type has exactly one system of record, declared in
  `config/module_catalog.json`.
- Modules communicate through public commands, queries, events, and typed
  integration contracts. They do not write another module's tables.
- Kernel dependencies point inward and never import business modules. Module
  dependencies are declared, public-only, and acyclic.
- The external communications system owns communication content and delivery
  state.
- The external collaborative-canvas system owns canvas operations and
  convergence state.
- A selected back-office system may own explicitly selected records; it never
  shares the application database.
- Blockchain may own anchor receipts only. It is never the operational source
  of truth, identity authority, workflow engine, or document store.
- Product-facing code, contracts, catalogs, UI, and documentation identify
  external systems by stable business role, not by company or product name.
  Exact implementation identities appear only where build reproducibility,
  security provenance, licensing, interoperability, or operations require
  them, as governed by ADR-0010.
- AI output is advisory until accepted through deterministic policy, a human
  decision, or an explicitly authorized low-risk command.

## Verification and completion

A change is not complete until, as applicable:

- architecture checks, formatters, linters, type checks, unit tests,
  integration tests, and end-to-end tests pass;
- code-size, cohesion, complexity, dependency, and boundary checks pass or have
  an explicit unexpired exception;
- authorization and tenant-isolation negative tests exist;
- idempotency, concurrency, audit, and failure behavior are tested;
- runtime health and user-visible behavior are smoke-tested;
- migrations, backup/restore, observability, rollout, and rollback are updated;
- `docs/STATUS.md` records verified facts and remaining gaps.

Never claim a declared or scaffolded capability is implemented or
production-ready without executable and runtime evidence.

## Security is part of every change

- Map attacker-controlled input, protected assets, trust boundaries, sensitive
  operations, and fail-closed behavior before adding a reachable surface.
- Review the changed source-to-sink paths for authorization bypass, tenant
  escape, injection, unsafe parsing, SSRF, file/process access, secret leakage,
  resource exhaustion, and supply-chain changes.
- Consequential commands require success and negative tests for permission,
  tenant mismatch, stale state, idempotency, audit, and failure behavior.
- Executable downloads, CI actions, container images, and direct dependencies
  require immutable identity or cryptographic verification and an update path.
- Run applicable formatter, compiler, tests, Sobelow, advisory, artifact,
  production-configuration, and secret checks before completion.
- Fix validated security defects in the same bounded increment when safe. If a
  fix depends on an unresolved product or deployment decision, keep the gate
  blocked and record the residual risk; never describe software as invulnerable.
