# ADR-0027: Previous application capability continuity

**Status:** Accepted product requirement; implementation remains gated  
**Date:** 2026-09-05

## Context

The product owner requires UOK Next to incorporate all features from previously
developed applications. Source inspection confirms a much broader feature set
than the target's qualified first proving operation. Dropping an app name or
replacing its stack must not silently drop its user outcomes.

The target working agreement requires one active delivery focus, native module
ownership and separate specialist authorities. A literal source-folder merge
would introduce incompatible frameworks, duplicate task/approval ownership,
multiple canvas engines and false maturity claims.

ADR-0026 was reserved for the communications contract already named in
`docs/STATUS.md` and now records that contract. This inventory decision does
not change the current delivery sequence.

## Decision

- Retain every previously developed capability as a tracked UOK Next outcome.
  Implement natively, integrate through a specialist role, or use a scoped
  local companion as its authority/runtime requirements demand.
- Preserve source and target maturity separately. Source presence, a README
  claim, a prototype or an unmerged PR never qualifies target behavior.
- Maintain `config/feature_continuity.json` and its per-source feature files.
  Every entry records source evidence, a lead target owner, integration mode,
  delivery gate, status and an acceptance profile. No existing source or entry
  may disappear in subsequent changes.
- Keep overlap visible. A shared implementation can satisfy multiple entries
  only when each entry's acceptance and lineage remain covered.
- Require target tests, runtime, reconciliation and rollback evidence bound to
  a target revision before declaring an entry qualified.
- Complete branch, archive, route/test and schema discovery before claiming an
  application inventory exhaustive. Retain unresolved aliases and upstream
  customization questions as explicit discovery gaps.
- Continue Gate 4 communications first. This inventory is a governance
  prerequisite for that work, not a second active runtime focus. Existing
  ADRs 0003, 0010, 0017 and 0018 remain in force.

## Source inventory

Exact implementation identities below are the minimum technical provenance
needed for source selection, interoperability and reproducible migration
review under ADR-0010. General product material uses the source roles.

| Source role | Exact repository and inspected revision | Selection finding |
|---|---|---|
| `legacy_operations` | [Soyuz-Tec/UOK](https://github.com/Soyuz-Tec/UOK/tree/d8fe71df008e63cf1e5780de006bd2e498ece7ba) | 13 manifests, all 122 status-labelled planning catalog rows and shared-feature table retained |
| `legacy_trade_prototype` | [Soyuz-Tec/Kayilan-CTRM](https://github.com/Soyuz-Tec/Kayilan-CTRM/tree/7cb7122375bce8d62201033baa67f6adf8ad0c2f) | Prototype scope, domain filenames, module workbench model and communications completion model inspected |
| `legacy_trade_intelligence` | [Soyuz-Tec/Kayilan_Atlas](https://github.com/Soyuz-Tec/Kayilan_Atlas/tree/a0d6e343d1674aa2c90a508e5ddff9eaf0ff21ea) | Default `master` branch; delivery sections, router inventory and source-to-lot route implementation inspected |
| `communications` | [Soyuz-Tec/k-comms](https://github.com/Soyuz-Tec/k-comms/tree/112aac9cfcf6459dbd5a351434d86d7492c7113b) | Platform scope, explicit deferrals and source/test tree inspected; local-staging claims not rerun |
| `canvas` | [Soyuz-Tec/k-board](https://github.com/Soyuz-Tec/k-board/tree/95cd6e89834d7dc23d7137456d016b7cd29df323) | Roadmap, storage/auth source paths and host ports inspected; README opening status is older than later persistence/auth sections |
| `desktop_file_tools` | [Soyuz-Tec/TwinTidy](https://github.com/Soyuz-Tec/TwinTidy/tree/fdea0d30ae8e1c65083bd831e1edc8dce25e7b60) | Current README disables destructive cleanup; older hardlink/cleanup descriptions are not activation authority |
| `portable_file_tools` | [Soyuz-Tec/twintidy-ports](https://github.com/Soyuz-Tec/twintidy-ports/tree/3ea2d5e27f1e54837100ac15ed9971eef1cbb1e3) | Read-only C/Rust CLI and GUI; limitations retained |
| `agent_operations_draft` | [Soyuz-Tec/kayilan-agentic-operations PR 3](https://github.com/Soyuz-Tec/kayilan-agentic-operations/pull/3), head `03ca3e1acfddce6ca3185b2266f6db3e6fbbd682` | Main is README-only; Phases 1-3 remain unmerged drafts; inspect latest draft's integration contract |
| `back_office_reference` | [Soyuz-Tec/odoo](https://github.com/Soyuz-Tec/odoo/tree/1868713dbd07e0b518f91dffe73e62d85e6ab9a6), `12.0` | Upstream fork; adopted/custom capability discovery remains open |
| `chain_reference` | [Soyuz-Tec/nitro](https://github.com/Soyuz-Tec/nitro/tree/e85be69012373182c141591c89be11eca40f16fc) | Upstream fork; no operational-chain authority inferred; ADR-0004 still governs |
| `tutorial_reference` | [Soyuz-Tec/interactive-tutorials](https://github.com/Soyuz-Tec/interactive-tutorials/tree/24083e89ae58b3f50157fca7b2086bea93e8349a) | Upstream fork; distinguish adopted educational capability from reference code |
| `profile_repository` | [Soyuz-Tec/Soyuz-Tec](https://github.com/Soyuz-Tec/Soyuz-Tec) | Empty profile configuration repository, not an application |
| `historical_trade_alias` | Historical name `Kayilan_RNC_app` | Not independently present in the connected repository inventory; reconcile rename/alias and archived packages before closing |

Target baseline:
[`dc44822b46e52699e8384d2fd39fa0242327d037`](https://github.com/Soyuz-Tec/UOK-Next/tree/dc44822b46e52699e8384d2fd39fa0242327d037).
The review did not execute any legacy application. Recorded source maturity
remains attributed to its source and must be requalified during migration.

## Decisions required before runtime integration

1. **Agent authority:** the draft integration contract assigns task/run state,
   policy, approvals, leases and evidence to its service. The target assigns
   those record families to platform modules. Resolve this through one explicit
   ownership/cutover ADR; do not run competing approval or retry engines. The
   inventory assigns `platform.agents` only as lead review responsibility and
   marks these entries blocked.
2. **Canvas authority:** communications includes a legacy whiteboard while the
   target has a separate canvas role. Preserve the whiteboard user outcome but
   choose one authoritative operation log and convergence engine.
3. **Local tools:** preserve local read-only scanning and review without giving
   UOK server commands arbitrary filesystem authority. Companion ownership,
   permission, installation and result-import contracts remain unresolved.
4. **Missing record coverage:** assign assets, service definitions, stock,
   calendars, intake and agent-memory records before implementing new writes.
   Lead module mappings do not amend `module_catalog.json` implicitly.
5. **Artifact and source rights:** inspect licenses and redistribution rights
   before reusing source, dependencies, fonts, icons or bundled assets.

## Validation, operations and rollback

The dependency-free Node validator runs under the existing pinned Node
toolchain. Negative tests cover removed features/sources, fabricated owners,
false qualification/completeness, weakened criteria, duplicate IDs, unsafe
paths and missing baseline commits. CI compares the previous Git inventory and
requires recorded decisions for material obligation changes. This validates
the register; runtime parity still requires workflow evidence and review.

Owning module: `platform.modules` for engineering governance. No application
commands, events, routes, tables, credentials or runtime permissions change.
No production or private business data is copied. Operational risk is an
incorrect mapping or a CI false positive; keep source locators and review the
diff. Rollback reverts this bounded repository change through protected
delivery, preserving its history for re-adoption.

## Supporting engineering publications

The source-driven incremental migration approach is consistent with Carnegie
Mellon's analysis of grouping related functionality and balancing migration
increments. It does not establish that any feature in this register works.
[CMU Software Engineering Institute, Incremental Modernization for Legacy
Systems, CMU/SEI-2001-TN-006](https://www.sei.cmu.edu/library/incremental-modernization-for-legacy-systems/).

Typed translation boundaries preserve the target's domain model while older
systems coexist. This supports the existing adapter approach without selecting
a cloud or moving business authority into the adapter.
[Microsoft Architecture Center, Anti-Corruption Layer
pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/anti-corruption-layer).

## Alternatives

- A source-folder merge: rejected because runtime, schema and authority
  conflicts are unresolved.
- Keeping the requirement only in conversation: rejected because later
  implementation could silently omit an older capability.
- Declaring parity from a checklist or legacy test count: rejected because
  neither proves the integrated target workflow.
