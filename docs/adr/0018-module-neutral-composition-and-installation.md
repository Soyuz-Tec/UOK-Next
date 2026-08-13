# ADR-0018: Module-neutral composition and installation

**Status:** Accepted

**Date:** 2026-08-12

## Context

Repository checks prove that the backend kernel imports no business module,
module dependencies point inward, declared record ownership is unique, and the
declared dependency graph is acyclic. The delivered application nevertheless
uses a static composition root and hard-coded Party and Sourcing navigation.
The initial migration also introduced kernel and Party tables together.

These choices are acceptable for the bounded Gate 3 modular monolith, but they
do not prove that modules can be installed, enabled per tenant, upgraded,
disabled, or independently retired. Describing the current application as an
installable module platform would therefore overstate its maturity.

## Decision

- The kernel remains unaware of Party, Product, Location, Sourcing, or any
  future business module. Business modules depend inward on kernel primitives.
- `platform.modules` owns module definitions, reviewed installation records,
  compatibility state, tenant enablement, surface registrations, and module
  verification receipts. It never owns a participating module's business data.
- A module manifest declares stable identifier and version, owned record types,
  dependencies, public commands, queries, events, permissions, migrations,
  rollback and retirement constraints, UI surfaces, operational objectives,
  and candidate/runtime verifiers.
- Initial modules remain compiled into one reviewed release. Installation is
  controlled activation of known code, not arbitrary runtime code loading.
  Downloaded or tenant-supplied executable plugins are outside this decision.
- The application composition root may know compiled module entry points. The
  product-neutral kernel and shared shell may consume only validated module
  descriptors. Navigation, routes, workspaces, and feature availability will
  be derived from enabled surface registrations instead of hard-coded business
  module names.
- Source dependency verification will derive cross-module imports and compare
  them with `config/module_catalog.json`. A cross-module reference must target
  the declared dependency's `Public` contract; undeclared, private, reverse, or
  cyclic dependencies fail CI. Frontend module imports receive an equivalent
  boundary rule.
- The repository retains one ordered migration history. Each migration must
  declare its owning module and compatibility/rollback boundary. Disabling a
  module removes entry points and consumers but preserves authoritative data
  until an explicit retention, export, and retirement command is approved.
- Cross-module foreign keys may protect tenant referential integrity inside the
  monolith. They do not transfer record ownership or authorize cross-module
  writes.
- A kernel-only boot and a disabled-module boot must pass before installability
  is claimed. Qualification must prove that disabled modules expose no command,
  route, consumer, scheduled work, or navigation surface while kernel health,
  audit, evidence, and enabled modules remain correct.
- Current static Gate 3 UI composition and the combined initial migration are
  recorded transition debt, not evidence of failed backend kernel neutrality.
  They must be retired through bounded increments after the active RFQ and
  quote-comparison vertical, unless that vertical needs a smaller prerequisite.

## Consequences

The modular monolith keeps one release and transaction boundary while gaining a
testable path to tenant-specific module activation and later service extraction.
The kernel stays stable as business breadth grows.

Manifest, compatibility, migration-ownership, UI-registry, and disabled-module
tests add engineering work. Runtime plugin loading remains deliberately absent,
which reduces extension flexibility but avoids an unbounded executable supply
chain and isolation problem.

## Alternatives

- Treat source folders as sufficient modularity: rejected because folders do
  not enforce dependencies, activation, compatibility, or retirement.
- Put module discovery and business navigation in the kernel: rejected because
  the kernel would learn product vocabulary and reverse dependency direction.
- Use unrestricted runtime plugins: rejected because executable provenance,
  isolation, compatibility, tenancy, and rollback are not yet qualified.
- Split each module into a service now: rejected because no measured scale,
  security, availability, residency, or release-cadence need justifies the
  distributed-system cost.
- Drop module data when disabled: rejected because disablement is not governed
  retention or legal deletion.

## Validation

- existing architecture, foundation, and code-discipline checks remain green;
- future implementation adds source-to-catalog and frontend-boundary checks
  that fail on undeclared or private cross-module imports;
- future module manifests prove unique identities, record ownership,
  permissions, and surfaces with an acyclic dependency graph;
- future kernel-only and disabled-module boots prove absence of business entry
  points;
  and
- `docs/STATUS.md` keeps installation and dynamic surface registration listed
  as unimplemented until executable evidence exists.
