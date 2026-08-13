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

Gate 3 advances sequentially rather than opening every context at once:

1. qualify tenant-authenticated party onboarding through real evidence and an
   exact human decision;
2. add product and sourcing-lane authority only after the first vertical passes;
3. continue through RFQ/comparison, commitment proposal, evidence approval,
   shipment readiness GO/HOLD, and the governed report.

The RFQ/comparison increment governed by ADR-0019 has passed protected
delivery, exact merged-revision qualification, two-replica failover, and
rendered desktop/mobile proof. It proves requisition, approved supplier
invitation, evidence-bound quotes, a deterministic snapshot, exact human
approval, and recovery without creating a purchase commitment.

The ADR-0020 purchase-commitment proposal increment has passed protected
delivery, exact committed- and merged-revision qualification, two-replica
failover, PostgreSQL/object-store proof, and rendered desktop/mobile checks. It
consumes one exact approved comparison, reauthorizes the current source chain,
binds internal proposal evidence, and records an exact human approval or HOLD.
Its product-neutral benchmark removes commercial-term re-entry while preserving
the proven separation between source selection, internal approval, and
downstream issuance. Proposal approval remains distinct from contract
formation, payment, inventory movement, and connector delivery.

The active increment is now shipment-readiness GO/HOLD. Before opening its
reachable command surface, compare the complete operator outcome with proven
enterprise execution workflows, record a measurable faster-path hypothesis,
and define ownership, evidence, freshness, exact decision, idempotency,
concurrency, audit, recovery, rollback, and downstream-effect boundaries in an
ADR. This remains the same single Gate 3 delivery focus.

Completing the first vertical is necessary evidence, not the Gate 3 exit by
itself.

AI remains advisory throughout the active shipment-readiness slice. The
delivered RFQ oracle and commitment proposal plus this next slice must preserve
deterministic commands, policies, evidence, exact human decisions, recovery,
and reportable outcomes.
They do not open model/tool execution, persistent agent memory, dynamic module
installation, or tenant module enablement. ADR-0017 and ADR-0018 define those
later prerequisites without changing the active delivery focus.

## Gate 4: Specialist integration

Exit when specialist systems, including bounded model and document-intelligence
workers where justified, are connected through typed, independently authorized
contracts with idempotency, health, failure, reconciliation, and end-to-end
evidence. Specialist execution never owns business command authority.

## Gate 5: Business breadth

Add shipment execution, quality, compliance, finance/risk, operations work,
public publishing, and BI one vertical outcome at a time. A module cannot
claim completion without real workflows, negative authorization tests, audit,
operational evidence, and recovery.

## Gate 6: Back-office integration

Select a maintained back-office system for the capabilities that should not be
rebuilt. Prove ownership, reconciliation, upgrades, degraded operation, and
rollback before production data cutover. Product-facing contracts retain the
role-based system identity regardless of implementation.

## Gate 7: Production qualification

Qualify threat model, tenant isolation, performance, accessibility,
observability, alerting, backup/restore, disaster recovery, supply-chain
security, immutable release promotion, staged deployment, and rollback.

## Gate 8: Optional evidence anchoring

Only after the off-chain evidence system is production-proven, implement a
chain-neutral anchor adapter and verify privacy, key management, reorganization
handling, cost, receipt reconciliation, legal purpose, and non-blocking failure.
