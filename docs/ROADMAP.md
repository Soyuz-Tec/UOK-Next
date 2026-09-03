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

The delivered shipment-readiness GO/HOLD increment is governed by ADR-0021. It
consumes one exact approved proposal, derives the commercial source and
server-owned checklist, accepts one case-bound readiness evidence bundle, and
records an exact GO or HOLD. The measurable faster path is three operator
actions, zero commercial-term re-entry, and zero cross-document navigation. It
deliberately creates no shipment, dispatch, inventory, finance, or external
effect. Protected delivery, exact merged-revision runtime, two-replica failover,
and rendered desktop/mobile evidence passed. The fifth vertical is delivered
and Gate 3 remains the single active focus.

The governed operational-reporting implementation is delivered under ADR-0023.
It has passed protected CI, exact merged-revision runtime,
PostgreSQL/object-store qualification, the full business journey,
deterministic reconciliation, two-replica failover, and rendered 1280-by-720
and 390-by-844 proof. Its live, read-only projection remains product-neutral
and never becomes business-command authority or a second system of record.

ADR-0024 adds the local attributable-user increment inside the existing Gate 3
identity boundary. The clone-local access code remains bootstrap administration;
it creates a server-revocable opaque session rather than a reusable bearer with
embedded authority. Unknown usernames share one bounded throttle bucket, and
the login boundary accepts JSON only. The access code itself is never a user.
regular users receive a temporary password, must replace it before any business
permission is issued, and then operate through an expiring database-revocable
session with one of two party-onboarding access profiles. This is required
multi-actor evidence for the proving operation, not a production identity or
federation selection.

The local attributable-user increment is delivered for local qualification on
protected-main revision `fc5bf65b3f3329553e41f58603ad6a5d06b47dc4`.
Exact-merge qualification proved both replicas, the complete business and
reporting journey, regular-user creation and forced password activation,
role-bounded party creation, revocation, and rendered desktop/mobile behavior.
It remains explicitly distinct from production identity or federation.

Completing the first vertical is necessary evidence, not the Gate 3 exit by
itself.

AI remains advisory throughout Gate 3. The delivered RFQ oracle, commitment
proposal, and shipment-readiness gate plus the next reporting slice must
preserve deterministic commands, policies, evidence, exact human decisions,
recovery, and reportable outcomes.
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
