# Development Continuity System

The repository, not a conversation, is the durable memory of the project.

## Start-of-task protocol

1. Confirm repository root, branch, remote, dirty state, and runtime target.
2. Read `AGENTS.md`, the product charter, architecture, ownership map, status,
   roadmap, and relevant ADRs.
3. Restate the one active focus and its unmet exit criteria.
4. Inspect the exact source, callers, contracts, tests, and runtime evidence for
   the intended slice.
5. Define the smallest change that advances the current gate.

## Change packet

Every non-trivial change must make these facts reviewable in its issue, commit,
PR, or `docs/STATUS.md` entry:

- outcome and user/business value;
- owning module and records;
- commands, queries, events, APIs, and UI surfaces changed;
- policy, tenant, privacy, audit, and external-side-effect impact;
- migrations and compatibility;
- tests and runtime evidence;
- deployment, monitoring, rollback, and remaining risk;
- ADR or documentation updates.

## End-of-task protocol

1. Run proportionate verification and record exact commands/results.
2. Separate implemented, locally verified, runtime-proven, and production-
   qualified claims.
3. Update `docs/STATUS.md` with the current revision, evidence, blockers, and
   the single next action.
4. Update the decision log/ADR when a material decision changed.
5. Update generated catalogs and architecture checks when contracts changed.
6. Preserve unrelated work and report any uncommitted or unpublished state.

## Focus controls

- One active roadmap gate and one active vertical outcome.
- No broad horizontal framework work without a consumer in the active slice.
- No new service, language, datastore, or infrastructure product without an
  ADR and a measured requirement.
- No duplicated business record for UI convenience; use projections.
- No “done” based on code presence alone.
- Every deferred item has a named gate or is explicitly rejected.

## Traceability

The project will maintain generated or machine-checked links among:

```text
Product outcome
  -> module and owner
  -> command/query/event contract
  -> policy and evidence requirement
  -> migration and data owner
  -> automated tests
  -> runtime/operational evidence
  -> roadmap exit criterion
```

The module catalog is the first machine-readable traceability artifact. API,
event, permission, migration, and metric catalogs will be added as their
respective kernel capabilities become executable.

