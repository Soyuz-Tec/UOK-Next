# Gate 3 First Business Operation Qualification

**Status:** Qualified for local development and CI

**Qualified protected-main revision:**
`d93e435e4c4bff9cb172409db04ebe99de5688af`

**Qualification date:** 2026-09-03

## Outcome

The first proving operation now runs from attributable party onboarding through
product and location authority, sourcing, RFQ and supplier quotes,
deterministic comparison, an internal purchase-commitment proposal, and an
exact shipment-readiness GO/HOLD decision. A governed operational report
reconciles the complete source chain, while PostgreSQL durable work publishes
transactional outbox events to an idempotent local handoff and recovers expired
leases after process loss.

This qualifies the roadmap's first end-to-end operation for local development
and CI. It does not qualify production identity, infrastructure, external
transport, a binding purchase contract or order, shipment execution, or
autonomous model/tool execution.

## Exit-criterion evidence

| Gate 3 criterion | Qualified evidence |
| --- | --- |
| Real API | Versioned tenant-scoped commands and queries execute every proving-operation stage; exact expected versions, idempotency keys, stable errors, and attributable actor context are enforced. |
| PostgreSQL | Module-owned records, composite tenant foreign keys, row-level policies, transactional audit/outbox writes, separate application and durable-worker roles, and forced tenant-isolation tests pass on the PostgreSQL 19 local target. |
| Object store | Bounded create-only evidence upload, collision rejection, read-after-write length and SHA-256 verification, tenant/subject binding, and deletion qualification pass against the pinned local S3-compatible runtime. |
| React UI | Protected revisions rendered the sequential workspaces and final six-stage report at desktop and 390-by-844 mobile sizes with no horizontal overflow, browser error, unnamed control, or visible action below 44 pixels. |
| Policy and audit | Server-owned permissions, exact human tasks, source-version revalidation, audit lineage, false-effect boundaries, revocation, role-bounded regular-user behavior, and negative authorization/tenant/replay tests pass. |
| Durable jobs | ADR-0025 schedules one PostgreSQL job per outbox event; a separate least-privilege worker leases, retries, dead-letters, observes, and writes one digest-only idempotent local-handoff receipt. |
| Governed reporting | One live repeatable-read projection reconciles six governed stages, five verified evidence references, bounded audit/delivery lineage, zero-stale failure policy, and three false authority boundaries. |
| Recovery | Both app processes stop; a receipt-present expired lease reconciles without increasing its attempt count; both replicas return; the settled report digest remains stable through four single-replica probes. |

## Protected delivery evidence

- PRs #17 through #20 delivered and closed party onboarding plus product and
  sourcing authority.
- PRs #22 through #27 delivered and closed RFQ/comparison, the internal
  commitment proposal, and shipment readiness.
- PRs #34 and #35 delivered and recorded governed operational reporting.
- PRs #36 and #41 delivered and recorded attributable clone-local regular-user
  access.
- PR #42 passed the protected foundation, application, and release jobs and
  delivered PostgreSQL durable outbox handoff as
  `977d5816429a0c8f345279b1d9dd483a7c58ba2d`.
- PR #43 passed the same protected jobs and corrected a pre-drain live-report
  qualifier race as `d93e435e4c4bff9cb172409db04ebe99de5688af` without
  weakening the terminal-state or failover assertions.

## Exact-revision runtime evidence

The complete local qualifier passed on exact protected-main revision
`d93e435e4c4bff9cb172409db04ebe99de5688af`:

- both replicas ran immutable image
  `832f32d39432ce6d8d72ce6575968c9dff9f236b8f33a3553089a1f2425be800`;
- release identity and readiness matched the full 40-character revision;
- the object-store round trip and the entire business/reporting journey passed;
- all 1,211 retained outbox events reached completed jobs and idempotent local
  handoff with zero pending, publishing, or dead-letter events;
- recovery job `a37214ae-3f09-4d11-8d13-1dc6a129b190` completed after both app
  processes stopped, without increasing its attempt count;
- the settled report projection was
  `9dbaf62eb47f47c73cf1403ca43109d822dd8d7109851b88af49a6844c8d9ea4`;
- four readiness, exact release-identity, and settled-report probes passed while
  one replica was deliberately unavailable.

Backend quality passed 136 tests with one object-store integration test reserved
for this immutable runtime qualifier. Frontend formatting, lint, TypeScript 7
and 6 compatibility, 13 test files with 19 tests, and the production build
passed. Foundation, architecture, code-discipline, database, object-storage,
external-identity, credential, static-security, production/local configuration,
compose, and diff checks passed.

## Residual risk and non-claims

- The local two-replica topology is not production availability evidence.
- PostgreSQL 19 Beta 2 remains local/CI-only until PostgreSQL 19 GA and a
  supported current minor are qualified.
- Production identity, managed secrets, trusted TLS ingress, monitoring and
  alert destinations, database/object backup and restore receipts, capacity,
  penetration, rollback, and disaster recovery remain blocked.
- No provider binding, credential, live connector, communication content,
  external delivery effect, consumer acknowledgment, or operator dead-letter
  redrive is implemented.
- The approved proposal and readiness GO are internal decision facts. They do
  not form a contract or order and create no shipment, dispatch, inventory,
  finance, payment, communication, or other external effect.
- Model/tool execution, persistent agent memory, module installation, and
  tenant module enablement remain deferred under their existing ADRs.

## Rollback

The application rollback target is the previously qualified protected revision
`fc5bf65b3f3329553e41f58603ad6a5d06b47dc4`. Gate 3 migrations are additive and
may remain in place during application rollback so retained evidence, jobs, and
receipts remain available for investigation. Destructive migration rollback is
not authorized without a separate retention and evidence decision.

## Gate 4 activation

Gate 4 is the only active delivery focus. Its first bounded increment defines a
provider-neutral external communications-system contract for business-object
links and delivery intent. Independent authorization, minimal projections,
idempotency, bounded receipts, health, failure, reconciliation, and a local
contract double must pass before any provider binding, credential, or live
transport is opened.
