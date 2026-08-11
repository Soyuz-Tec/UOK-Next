# UOK Next Working Agreement

These instructions apply to the entire repository.

## Establish authority before work

Before changing code or architecture, read:

1. `docs/PRODUCT_CHARTER.md`
2. `docs/ARCHITECTURE.md`
3. `docs/MODULE_OWNERSHIP.md`
4. `docs/STATUS.md`
5. `docs/ROADMAP.md`
6. Relevant ADRs under `docs/adr/`

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
- K-Comms owns communication content and delivery state.
- K-Board owns collaborative canvas operations and convergence state.
- Odoo may own explicitly selected back-office records; it never shares the
  application database.
- Blockchain may own anchor receipts only. It is never the operational source
  of truth, identity authority, workflow engine, or document store.
- AI output is advisory until accepted through deterministic policy, a human
  decision, or an explicitly authorized low-risk command.

## Verification and completion

A change is not complete until, as applicable:

- architecture checks, formatters, linters, type checks, unit tests,
  integration tests, and end-to-end tests pass;
- authorization and tenant-isolation negative tests exist;
- idempotency, concurrency, audit, and failure behavior are tested;
- runtime health and user-visible behavior are smoke-tested;
- migrations, backup/restore, observability, rollout, and rollback are updated;
- `docs/STATUS.md` records verified facts and remaining gaps.

Never claim a declared or scaffolded capability is implemented or
production-ready without executable and runtime evidence.

