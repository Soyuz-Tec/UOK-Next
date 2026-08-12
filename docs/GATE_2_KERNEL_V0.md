# Gate 2 Kernel v0 Qualification

**Status:** Qualified for local development and CI

**Qualified protected-main revision:**
`2e96d88df67878d9b7023a49020487dfff2834ac`

**Qualification date:** 2026-08-12

## Outcome

Kernel v0 supplies the deterministic, tenant-aware command and evidence
primitives required before a user-facing business workflow or autonomous
execution surface can be built. It is a modular-monolith foundation, not a
claim that the first business operation or a production environment is ready.

## Exit-criterion evidence

| Gate 2 criterion | Qualified evidence |
| --- | --- |
| Tenant and actor context | Trusted command context carries validated tenant, actor, correlation, and named permissions; application predicates and forced database row-level isolation fail closed. |
| Policy | Consequential proposal, approval, reconciliation, and read paths require exact named permissions and include negative permission tests. |
| Module catalog | Machine verification confirms 19 unique modules, 6 role-based external systems, and 95 uniquely owned record types. |
| Commands | Party onboarding, human-task, connector-receipt, and agent-plan transitions use public application commands with bounded validation and stable errors. |
| Idempotency | Command receipts replay an identical request and reject key reuse with a different canonical payload. |
| Optimistic concurrency | Version checks, locked reads, one-way lifecycles, and optimistic database locks reject stale or repeated decisions. |
| Events and outbox | Successful mutations atomically append versioned outbox events; failed transactions leave no partial event evidence. |
| Audit and evidence | Successful mutations atomically append actor, tenant, reason, classification, resource, and metadata evidence. Evidence bytes use a bounded, digest-verified, create-only object boundary. |
| Human tasks | PR #12 added exact tenant/subject/version review tasks, task-specific permission, atomic completion, row-level isolation, and substitution/replay negative tests. |
| Connector receipts | PR #13 added immutable attempt identity, bounded digest/reference-only outcomes, retry lineage, deadlines, recovery states, and no live transport. |
| Governed agent plans | PR #14 added bounded acyclic advisory plans, server-derived digests, exact human review, execution-field rejection, and permanent `execution_authorized: false` review evidence. |

## Protected delivery evidence

- PR #12 merged the human-task increment as
  `0c3c8e510575cdae5688a6a0116b5b90a9ceb512`.
- PR #13 merged the connector-receipt increment as
  `456e7b678f756e9f69889ced728e2b2585b447e1`.
- PR #14 merged the governed-plan increment as
  `2e96d88df67878d9b7023a49020487dfff2834ac`.
- Each increment passed the protected foundation, application, and release
  jobs. Complete security diff reviews of the connector and agent increments
  closed every changed production/migration worklist row with complete
  coverage and no reportable finding.

## Integrated verification

The following checks passed on exact protected-main revision
`2e96d88df67878d9b7023a49020487dfff2834ac`:

```powershell
mix quality
.\scripts\verify_foundation.ps1
.\scripts\verify_architecture_boundaries.ps1
.\scripts\verify_code_discipline.ps1
.\scripts\verify_database_policy.ps1
.\scripts\verify_external_identity_policy.ps1
.\scripts\verify_object_storage_policy.ps1
.\scripts\verify_web_foundation.ps1
.\scripts\deploy_local_qualification.ps1
```

Results:

- compilation with warnings as errors passed;
- 67 tests passed and one environment-gated object-store test was excluded;
- static analysis and the web security scan reported no issue;
- architecture boundaries covered 39 production source files;
- code-discipline checks covered 66 production files with no active exception;
- database, object-storage, external-identity, foundation, and web policies
  passed;
- release image
  `babcfa8667e1aad4be24f6b6df6a44c34e94bb069b959dd669e772464d3d7174`
  embedded the exact 40-character merged revision;
- both application replicas ran that identical image;
- readiness, release identity, and authenticated metrics passed;
- object create, collision rejection, read-after-write length/digest
  verification, and delete passed;
- four consecutive readiness and release probes passed while one replica was
  deliberately unavailable.

## Residual risk and non-claims

- PostgreSQL 19 Beta 2 remains the local/CI compatibility target; production
  requires PostgreSQL 19 GA and a current supported minor.
- The local database is a single dependency. No production database HA,
  fencing, WAL/PITR, backup/restore receipt, or disaster-recovery proof exists.
- Production identity and sessions, user-facing business APIs, module business
  UI, durable outbox delivery, job scheduling, evidence metadata commands,
  live connectors, runbook definitions, model/tool execution, BI projections,
  and evidence anchoring are not implemented.
- The two-replica local qualifier is neither a selected production topology nor
  production availability evidence.

## Rollback

The release rollback target is the prior qualified immutable revision
`456e7b678f756e9f69889ced728e2b2585b447e1`. The Gate 2 migrations are additive
and may remain unused during release rollback. A migration rollback is allowed
only after confirming that no retained human-task, connector-receipt, or agent
plan evidence is required.

## Gate 3 activation

Gate 3 is the only active delivery focus. Its first bounded vertical is a real
tenant-authenticated party-onboarding journey through the API, database,
evidence boundary, human review, module UI, audit/outbox, telemetry, and
recovery tests. Later proving-operation stages remain blocked until that first
vertical is executable end to end without prototype-only state.
