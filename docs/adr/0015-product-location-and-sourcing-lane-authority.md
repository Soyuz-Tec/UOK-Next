# ADR-0015: Product, location, and sourcing-lane authority

**Status:** Accepted

**Date:** 2026-08-12

## Context

The first Gate 3 vertical proved tenant-authenticated party onboarding through
verified evidence and an exact human decision. The proving operation now needs
governed product and route references plus a sourcing lane that binds them to
an approved supplier. Combining these records in one table would obscure their
different ownership and allow later RFQ work to mutate copied master data.

The increment must remain smaller than RFQ/comparison. It must also reuse the
existing command, evidence, task, audit, outbox, tenant, and UI boundaries
instead of creating another policy or workflow mechanism.

## Decision

- `master.products` owns products. The first contract creates and reads active
  products identified by a tenant-stable key, display name, product kind, and
  governed base-unit code.
- `master.locations` owns locations and route references. The first contract
  creates and reads active tenant locations identified by a stable key, name,
  country code, and location kind.
- `trade.sourcing` owns sourcing lanes. A lane references one approved supplier
  party, one active product, and distinct active origin and destination
  locations. It never copies their descriptive or lifecycle fields.
- Each module owns its table, pure validation, persistence port, public command
  and query contract, permissions, audit representation, and outbox event.
  `trade.sourcing` depends only on the public contracts of the three master-data
  modules plus `platform.evidence` and `platform.workflow`.
- Product and location creation are attributable idempotent commands that make
  the bounded reference record active immediately. Deactivation, hierarchy,
  conversion graphs, classifications, quality templates, corridors, and route
  optimization remain outside this increment.
- A sourcing lane starts in `draft`. Evidence submission requires a verified
  object bound to the exact lane and atomically opens one version-bound review
  task. Approve or HOLD consumes that exact task in the same transaction as the
  lane transition, command receipt, audit records, and outbox events.
- Before lane creation, and again inside its command transaction, the server
  verifies the supplier is approved and every referenced master record is
  active in the same tenant. Database composite foreign keys reinforce tenant
  identity; PostgreSQL row-level security is forced on all new tables.
- The versioned API exposes bounded create, list, and detail queries plus lane
  evidence and decision commands. The React UI remains presentation-only and
  composes module-owned product/sourcing surfaces into the Gate 3 workspace.
- The supported qualifier must execute the real sequence: approved party,
  product, two locations, lane draft, verified evidence, exact task, approval,
  and final read. RFQ, quote comparison, commercial commitment, and shipment
  execution are explicitly excluded.

## Consequences

The application gains an authoritative bridge from approved counterparties to
an evidence-backed trading route without weakening module ownership. More
records and permissions expand the tenant and authorization surface, so
cross-tenant reference substitution, inactive or unapproved references, stale
state, replay conflict, task substitution, and row-level isolation require
negative tests.

The initial active reference lifecycle is deliberately narrow. Future changes
to units, classifications, location hierarchy, route validity, or reference
retirement require explicit commands and compatibility rules rather than
generic update endpoints.

## Alternatives

- Store product and location text directly on the lane: rejected because it
  creates shadow master data and ambiguous correction authority.
- Let `trade.sourcing` write master-data tables in one repository transaction:
  rejected because it violates module ownership and makes later extraction or
  policy changes unsafe.
- Open RFQ and quote comparison in the same increment: rejected because the
  reference and lane contracts need executable proof first.
- Approve lanes without evidence or a human task: rejected because missing
  evidence must produce HOLD and consequential decisions require attributable
  authority.

## Validation

- command and API tests cover success, validation, authorization, tenant and
  reference substitution, unapproved supplier, identical endpoints, stale
  state, idempotent replay/conflict, exact-task consumption, audit, outbox, and
  transactional rollback;
- database tests cover composite tenant foreign keys, constraints, forced RLS,
  and least-privileged runtime access;
- frontend tests and rendered desktop/mobile proof cover the real server-owned
  workflow without horizontal overflow or browser errors;
- architecture, format, compiler, static analysis, advisory, security diff,
  immutable release, two-replica identity, object-store recovery, failover, and
  exact-revision qualification remain delivery gates.
