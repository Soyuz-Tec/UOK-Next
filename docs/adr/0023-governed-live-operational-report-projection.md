# ADR-0023: Governed live operational-report projection

**Status:** Accepted

**Date:** 2026-08-25

## Context

The first proving operation now reaches an evidenced shipment-readiness GO or
HOLD without creating shipment, dispatch, inventory, finance, or external
effects. Gate 3 next requires an operational and management report that makes
the whole party-to-readiness outcome understandable without creating a second
system of record or business-command path.

Proven enterprise reporting workflows consistently provide a role-authorized
summary, visible data freshness, drill-through lineage, source status, refresh
or failure history, and reconciliation controls. They often require separate
navigation between a dashboard, source records, audit detail, and delivery
monitoring. UOK keeps the controls but presents the complete governed chain in
one read-only workbench.

The measurable version-one hypothesis is zero field re-entry, zero cross-record
navigation, and an automatically loaded latest report. Selecting another
readiness case is one operator action. The report must not weaken source
permissions, conceal stale or unreconciled data, or gain mutation authority.

## Decision

- `intelligence.bi` owns `operational_report_projection`. Version 1 has one
  grain: an exact tenant-owned `shipment_readiness_case` and its complete
  source lineage.
- The projection is generated on demand from module public queries inside one
  PostgreSQL repeatable-read, read-only transaction. Version 1 creates no
  projection table, materialized view, background refresh job, cache, export,
  or analytical copy.
- Access requires `reports:operational:read` plus every underlying source-read
  permission exercised by the projection. The reporting module never bypasses
  another module's public authorization contract and never accepts tenant or
  actor identity from request data.
- `trade.shipments` supplies the exact readiness record and revalidates its
  current approved commercial source. `trade.sourcing`, `master.parties`,
  `master.products`, and `master.locations` supply current governed dimensions
  through public queries. Missing, stale, substituted, held, or unauthorized
  source data fails closed without returning a partial report.
- `platform.evidence` supplies a bounded lineage view over append-only audit
  events and kernel outbox delivery state. It returns no event payload, raw
  evidence bytes, storage receipt, or unrestricted audit metadata.
- The report declares definition version, grain, source identifiers and
  versions, UTC observation time, freshness mode, reconciliation status and
  deterministic SHA-256, metric semantics, stage status, evidence references,
  audit lineage, delivery-state counts, and explicit authority flags.
- The reconciliation digest excludes observation time and is computed from a
  deterministic canonical projection. Identical authoritative state produces
  the same digest across repeated reads.
- Version 1 metrics use the approved commercial-source grain and currency:
  quantity, unit price, approved total, delivery days, required date, evidence
  count, audit-event count, and outbox status counts. No currency conversion,
  aggregation across grains, forecast, accounting fact, or inferred KPI is
  introduced.
- Every response declares `source_of_truth: false`,
  `business_mutation_authorized: false`, and `external_effect_created: false`.
  The browser offers no business mutation from the reporting surface.
- Report generation emits bounded duration and outcome telemetry. A query
  failure returns no stale or partial substitute; the browser removes the
  failed selection's prior result and presents an attributable retry path.

## Consequences

Operators and managers receive a current, attributable report without a data
warehouse, refresh scheduler, or duplicate business truth. Repeatable-read
isolation and deterministic reconciliation make the point-in-time claim
explicit and testable.

Version 1 deliberately favors correctness over large-volume analytical speed.
Measured latency, concurrency, retention, or cross-operation analysis may later
justify an owned persisted projection or analytical execution plane. That
change requires freshness objectives, consumer receipts, reconciliation,
backfill, retention, failure recovery, rollout, and rollback evidence.

## Alternatives

- Persist a denormalized report row during each business command: rejected
  because it couples modules transactionally and can make the projection look
  authoritative.
- Query module-private tables from the reporting module: rejected because it
  bypasses ownership, authorization, and compatibility contracts.
- Build the report in the browser from many APIs: rejected because the browser
  cannot guarantee one database snapshot, deterministic reconciliation, or
  complete permission enforcement.
- Introduce a separate analytical database or event stream: rejected because
  the proving workload does not justify another data platform or recovery
  boundary.
- Allow report-only permission to reveal all source data: rejected because a
  reporting surface must not amplify source privileges.

## Validation

- application and API tests cover success, exact version, deterministic digest,
  report permission, each source permission class, tenant substitution,
  current-source failure, bounded lineage, and no-authority flags;
- database tests prove the snapshot transaction is read-only and source queries
  remain protected by forced row-level security;
- telemetry tests prove duration and success/rejection outcomes without tenant,
  actor, record, or sensitive payload labels;
- UI tests and rendered desktop/mobile evidence prove automatic latest-report
  loading, one-selection navigation, freshness and reconciliation visibility,
  semantic tables, keyboard access, and no report mutation control; and
- protected delivery, exact committed and merged images, PostgreSQL/object
  storage, two-replica failover, the full business journey, and report runtime
  proof remain mandatory before the final Gate 3 vertical is delivered.
