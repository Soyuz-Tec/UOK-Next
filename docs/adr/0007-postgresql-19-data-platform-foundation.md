# ADR-0007: PostgreSQL 19 data-platform foundation

**Status:** Accepted for compatibility qualification; production activation gated on PostgreSQL 19 GA

**Date:** 2026-08-11

## Context

UOK Next already uses PostgreSQL for tenant-scoped commands, audit evidence,
outbox records, and module data. The initial design proved transactional and
row-level isolation behavior, but it did not define the database as a complete
production subsystem. Cluster identity, certificate trust, connection budgets,
role topology, high availability, WAL archival, point-in-time recovery,
monitoring, maintenance, upgrades, and restore evidence remained platform
assumptions. Tenant child records also referenced command receipts by a global
identifier without a database-enforced tenant match.

PostgreSQL 19 Beta 2 is available in August 2026 and GA is planned for
September 2026. The PostgreSQL project recommends beta testing but explicitly
advises against production use.

## Decision

- PostgreSQL 19 is the only target major version. Beta 2 is digest-pinned for
  local and CI compatibility qualification; production rejects prerelease
  server versions and must use the current supported PG19 minor release.
- New clusters use UTF-8, the built-in `PG_UNICODE_FAST` locale, UTC, data
  checksums, and SCRAM-SHA-256. Language-specific presentation ordering uses
  explicit reviewed collations instead of changing storage identity.
- Production connections require Postgrex peer and hostname verification with
  an explicitly mounted CA trust file. Application writes target a primary.
- One database and migration history remain the modular-monolith boundary.
  Module-prefixed tables remain in the application schema until measured
  ownership or security pressure justifies another ADR.
- Production separates non-login object ownership, migration, application,
  outbox, monitoring, backup, replication, and break-glass authority. Runtime
  roles cannot own objects, inherit privileges, replicate, or bypass RLS.
- Tenant relationships include `tenant_id` in unique and foreign-key
  constraints. RLS is defense in depth, not a substitute for relational
  integrity.
- The application pool budget is calculated across all replicas and worker
  roles. A pooler is optional and must be justified by measured connection
  pressure; migrations always bypass transaction pooling.
- Production requires fenced primary failover, continuous WAL archival,
  encrypted and immutable off-platform backups, PITR, monitored archive lag,
  and recurring isolated restore drills. Replication is not a backup.
- `pg_stat_statements`, cumulative statistics, I/O timing, lock waits,
  checkpoints, vacuum/freeze state, WAL, replication lag, storage, and
  connection saturation form the minimum observability contract. Query text
  and parameters are treated as potentially sensitive.
- Schema change uses forward-compatible expand/contract steps, bounded lock
  and statement timeouts, one migration job, and explicit handling for
  non-transactional concurrent indexes. Destructive changes require backup,
  compatibility, rollback, and retention evidence.

The complete contract and unresolved platform gates live in
`docs/DATABASE_ARCHITECTURE.md`; machine-readable invariants live in
`config/database_policy.json`.

## Consequences

PG19 incompatibilities are discovered before GA and the database target no
longer drifts silently between development, CI, and production. The local PG18
volume is preserved while a new version-specific PG19 volume is initialized.
The application gains stronger tenant referential integrity and authenticated
database TLS. Production is intentionally still blocked until a platform can
prove the declared HA, backup, restore, monitoring, capacity, and upgrade
contracts.

Using a prerelease database in compatibility environments creates churn risk,
so the image digest and driver compatibility must be refreshed for every beta,
release candidate, and GA build. No production data may be placed on a beta or
release-candidate cluster.

## Alternatives considered

- Remain on PostgreSQL 18 until PG19 GA: rejected because the August
  compatibility window is useful and the user selected PG19 as the foundation.
- Run PG19 Beta 2 in production: rejected because upstream warns that beta
  builds can contain serious or backward-incompatible defects.
- Use schema-per-tenant or database-per-tenant immediately: deferred because
  the current shared-schema model has enforced RLS and lower operational
  complexity; isolation tiers may be added through a later evidence-backed ADR.
- Add PgBouncer immediately: deferred until connection saturation is measured;
  transaction pooling changes session semantics and migration locking.
- Treat streaming replicas as backups: rejected because replicas reproduce
  operator mistakes and corruption and do not provide independent PITR.

## Validation

- PG19 core cluster assertions run in CI before application tests;
- local qualification verifies the extended statistics and configuration
  baseline on a fresh PG19 cluster;
- readiness and the release migration entrypoint reject the wrong major and
  reject prerelease servers outside an explicitly marked qualification profile;
- behavioral tests prove that cross-tenant receipt relationships fail at the
  database constraint boundary;
- production configuration tests prove CA-backed TLS and primary targeting;
- a PG19 GA image digest, HA topology, backup/PITR restore receipt, capacity
  result, and failover receipt remain mandatory before production promotion.
