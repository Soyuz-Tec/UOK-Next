# Delivery Roadmap

This roadmap uses evidence gates rather than feature-count targets. There is
exactly one active focus, recorded in `docs/STATUS.md`.

## Gate 0: Durable foundation

Exit when:

- product charter, architecture, ownership, roadmap, continuity, and initial
  ADRs are accepted;
- modular-monolith and engineering standards are explicit and machine-checked;
- the machine-readable module catalog has unique module and record ownership;
- architecture verification runs locally and in CI;
- code-discipline verification runs locally and in CI;
- the target repository, branch, remote, and versioning convention are fixed;
- required toolchains are pinned and reproducibly installable.

## Gate 1: Framework and kernel skeleton

Exit when:

- Phoenix/OTP application and React/TypeScript shell build reproducibly;
- PostgreSQL and local object-storage dependencies start through one supported
  development command;
- an Ash-versus-explicit-Elixir spike implements the same narrow resource,
  action, policy, tenant, and audit behavior and records the decision;
- CI runs format, lint, type, architecture, unit, dependency, and secret checks;
- release identity and health endpoints are proven in a local container.

## Gate 2: Kernel v0

Exit when tenant/actor context, policy, module catalog, commands, idempotency,
optimistic concurrency, events/outbox, audit/evidence, human tasks, connector
receipts, and governed agent plans are integrated and negative-tested.

## Gate 3: First end-to-end business operation

Exit when the proving operation in `docs/PRODUCT_CHARTER.md` works through the
real API, database, object store, UI, policies, audit, jobs, reporting, and
recovery path without prototype-only state.

## Gate 4: Specialist integration

Exit when K-Comms and K-Board are connected through typed, independently
authorized contracts with idempotency, health, failure, reconciliation, and
end-to-end evidence.

## Gate 5: Business breadth

Add shipment execution, quality, compliance, finance/risk, operations work,
public publishing, and BI one vertical outcome at a time. A module cannot
claim completion without real workflows, negative authorization tests, audit,
operational evidence, and recovery.

## Gate 6: Back-office integration

Select Odoo or another maintained system for the back-office capabilities that
should not be rebuilt. Prove ownership, reconciliation, upgrades, degraded
operation, and rollback before production data cutover.

## Gate 7: Production qualification

Qualify threat model, tenant isolation, performance, accessibility,
observability, alerting, backup/restore, disaster recovery, supply-chain
security, immutable release promotion, staged deployment, and rollback.

## Gate 8: Optional evidence anchoring

Only after the off-chain evidence system is production-proven, implement a
chain-neutral anchor adapter and verify privacy, key management, reorganization
handling, cost, receipt reconciliation, legal purpose, and non-blocking failure.
