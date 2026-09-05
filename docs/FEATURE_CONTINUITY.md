# Previous application feature continuity

**Requirement date:** 2026-09-05  
**Decision:** [ADR-0027](adr/0027-previous-application-capability-continuity.md)  
**Register:** [feature_continuity.json](../config/feature_continuity.json)

## Required outcome

UOK Next must incorporate every capability developed in the previous
applications. A capability may be delivered by a native UOK module, a governed
specialist integration, or a scoped local companion. Consolidating overlapping
features must preserve their supported outcomes, controls, data lineage, user
access and recovery behavior. A new screen or an inventory entry is not parity.

Earlier planned features remain visible in the backlog with their original
maturity. A feature is not dropped merely because its source is an older app,
a prototype, an unmerged branch, a desktop utility or a different runtime.
Production activation still requires the existing evidence gates.

## Initial discovery baseline

The initial register has **488 capability entries in eight application
lineages**. Entries include granular features, declared commands and overlapping
workflow families; the count is not a count of unique features or completed
migrations. No entry is qualified in this register yet. Existing UOK Next Gate
1-3 evidence remains valid within its recorded scope; full parity with a broader
legacy feature must be characterized separately.

| Source role | Entries | Intended UOK destination |
|---|---:|---|
| Earlier operations platform | 264 | Work/planning, parties, products, locations, shipments, compliance, reporting, module lifecycle and shared UI |
| Trade prototype | 84 | Sourcing, contracts, finance, evidence, workflow, reference data and communications integration |
| Trade intelligence application | 50 | Quality/field capture, lots/farms, logistics, intelligence, evidence, partner access and public publishing |
| Communications platform | 24 | External communications system through `platform.integrations` |
| Collaborative canvas | 32 | External collaborative-canvas system |
| Desktop file review tool | 12 | Scoped local companion; ownership and integration decision required |
| Portable file review tools | 6 | Read-only local companion; ownership and integration decision required |
| Agent operations draft | 16 | `platform.agents` after explicit source/target ownership reconciliation |

The register retains all 122 explicitly status-labelled rows from the earlier
planning feature catalog and command lists from all 13 earlier operations
module manifests. It also records prototype scope, communications completion
models, intelligence delivery sections, canvas roadmap entries and the latest
agent-operations draft. Exact repositories, revisions and source-selection
findings live in ADR-0027's technical provenance section.

Discovery is **initial**, not exhaustive. Three upstream forks need a check for
adopted/custom features; one historical trade-app name needs alias/archive
reconciliation. The empty profile repository is classified as non-application.
Unmerged branches, archived application packages, source routes, tests, data
schemas and actual workflows still need characterization before an application
lineage can be marked completely inventoried. These gaps cannot be removed
from the register to manufacture completeness.

## Delivery and ownership

1. Preserve the current Gate 4 communications-contract focus. Its design must
   account for messaging, membership, attachments, calls, notifications,
   object links, communication-to-task candidates and intentional evidence
   promotion, even when the first implemented contract is narrower.
2. Qualify the canvas and bounded agent/worker contracts under Gate 4. Choose
   exactly one convergence owner for legacy whiteboard behavior. Resolve the
   conflicting agent task/run/approval/evidence ownership declarations before
   any runtime integration or retry mechanism is enabled.
3. Deliver business breadth under Gate 5 in bounded verticals: work management
   and Gantt; canonical master data and contacts; source-to-lot/field quality;
   logistics and compliance; sales/contracts and finance; intelligence,
   exports, public publishing and partner access. Dependency evidence may
   refine this sequence through the existing ADR process.
4. Evaluate back-office capabilities under Gate 6. An upstream fork is evidence
   to inspect, not proof that every upstream module was developed or adopted.
5. Qualify complete user journeys, migration/reconciliation, recovery and
   operational controls before the relevant production cutover.

The mapping is a lead delivery responsibility, not a new system-of-record
declaration. Assets, stock positions, service profiles, calendar appointments,
agent memory, public intake and desktop cleanup may need narrower record
ownership decisions. `config/module_catalog.json` remains authoritative. No
source schema, duplicate workflow engine, communication-content store or
canvas merge engine is imported by this increment.

## How to complete one entry

For the entry's pinned source revision and locator:

1. Characterize the complete source outcome, edge cases, permissions, data,
   integration effects, failure recovery and declared limitations. Read source
   and tests; rerun the relevant source workflow when available.
2. Map it to named target commands/queries/events and exactly one record owner.
   Split or cross-reference overlapping outcomes without removing their IDs.
3. Specify acceptance examples using `required_outcome` and the named
   `acceptance_profile`. Add feature-specific boundary cases, numeric or
   scheduling oracles, accessibility and operational budgets where relevant.
4. Implement the bounded slice, including idempotency, tenant isolation,
   concurrency, evidence, failure, rollback and migration reconciliation.
5. Record target revision and evidence paths of kinds `tests`, `runtime`,
   `reconciliation` and `rollback` before setting `target_status: qualified`.
   Review the evidence itself: the verifier checks structure and references,
   not the truth of a runtime claim.

Source maturity is separately recorded as `reported_maturity`. It is a source
claim observed during this inventory, not a fresh independent runtime test.
`planned`, `partial` and `blocked` retain obligations; only `qualified` is a
target parity claim. A qualified entry still is not a production-readiness
claim outside its recorded qualification scope.

## Automated controls

```sh
node --test test/architecture/feature_continuity_test.mjs
node scripts/verify_feature_continuity.mjs --baseline-ref <full-base-commit-sha>
```

The Node version is the existing repository-pinned toolchain. No new runtime
dependency is introduced. CI uses its base commit and full checkout history to
compare prior inventory entries, including entries held in separate files.

The verifier rejects unknown owners, duplicate IDs, missing evidence,
unresolved ownership marked deliverable, false discovery completeness,
out-of-repository file references and removals of previously recorded sources
or entries. Changing an outcome, lead owner, integration mode or acceptance
profile requires a recorded ADR reference. Existing acceptance profiles are
immutable: add a versioned replacement and explain its use. Semantic reduction
and false evidence still require human review; this is not a formal proof that
all prior behavior has been discovered or migrated.

## Privacy, operations and rollback

No business records, private messages, credentials or local user files are
migrated by this inventory. Future migrations preserve classification and
purpose: individual CIS/KYC/KYB/signatory/UBO business records are restricted
business data, while private personal records remain outside business storage.

The source desktop tool currently disables destructive cleanup; its ports are
read-only. Retaining those controls is part of parity. A companion integration
cannot turn a server or an agent into an unrestricted local filesystem actor.

This increment adds repository governance and validation only. It changes no
API, event, database schema, production configuration or runtime permission.
Rollback reverts the inventory/check/documentation commit through normal
protected delivery. Keep the historical inventory in Git; retiring any source
application remains blocked until its full applicable parity is evidenced.
