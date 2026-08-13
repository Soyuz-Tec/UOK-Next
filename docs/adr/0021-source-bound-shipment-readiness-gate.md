# ADR-0021: Source-bound shipment-readiness GO/HOLD gate

**Status:** Accepted

**Date:** 2026-08-13

## Context

The delivered purchase-commitment proposal proves an exact, source-derived,
internally approved commercial intent without creating a contract, order, or
external effect. The next proving-operation step must determine whether work is
ready to advance toward shipment execution while preserving that separation.

Proven enterprise execution workflows consistently distinguish planning and
readiness from release or ship confirmation. They use explicit statuses,
eligibility rules, evidence or operational signals, named holds and reasons,
and a later privileged execution step. They also commonly require operators to
move among source, load, work, document, and exception views before deciding.

UOK preserves the controls but removes the handoff. The measurable version-one
hypothesis is three operator actions: select one approved proposal, attach one
governed readiness evidence bundle, and decide GO or HOLD. The workflow accepts
zero commercial-term fields, requires no cross-document navigation, and creates
zero dispatch, inventory, finance, or external effects.

## Decision

- `trade.shipments` owns `shipment_readiness_case`. It is an internal gate over
  one exact approved `purchase_commitment_proposal`; it is not a shipment plan,
  load, container, booking, dispatch instruction, warehouse release, inventory
  movement, invoice, or external message.
- Creation accepts only a stable identifier, proposal identifier, exact
  proposal version, and attributable reason. `trade.contracts` locks and
  revalidates the approved proposal and its current sourcing chain through its
  public contract. The server derives every commercial term, source version,
  supplier, route reference, required date, and evidence digest.
- One proposal can create at most one readiness case. The case stores a bounded
  immutable source snapshot and checklist version 1. The browser, model, and
  integrations cannot submit checklist outcomes or material source fields.
- Checklist version 1 contains server-owned signals for an exact approved
  proposal, a current sourcing chain, verified commercial evidence, and a
  verified operational-readiness evidence bundle. The first three are derived
  at creation. The operational signal remains pending until a verified evidence
  object bound to the exact case is submitted.
- Evidence submission is allowed from `draft` and `hold`. It repeats source
  validation under locks, requires a verified case-bound evidence object,
  records a complete versioned checklist, clears any prior HOLD decision, and
  atomically opens one exact-version human task. Resubmission after HOLD is the
  recovery path; the previous immutable evidence and audit history remain.
- The named decision is GO or HOLD. GO repeats current source and checklist
  validation, then completes the exact human task using the platform's governed
  approval resolution. HOLD remains available even when the source has drifted
  so unsafe work can close. Both outcomes atomically record case state, command
  receipt, actor and reason, append-only audit, and outbox events.
- Every public response, audit record, and event explicitly records
  `shipment_created: false`, `dispatch_created: false`,
  `inventory_effect_created: false`, `finance_effect_created: false`, and
  `external_effect_created: false`. GO is a review fact, never reusable
  execution authority.
- PostgreSQL reinforces tenant isolation with composite tenant references,
  forced row-level security, one-case-per-proposal uniqueness, bounded source
  and checklist snapshots, lifecycle completeness, positive versions, and
  optimistic concurrency.
- The initial workbench shows source terms, evidence lineage, and checklist
  status together. It offers only the source selection, evidence upload, and
  exact GO/HOLD actions needed for this outcome.
- Shipment planning, carrier or warehouse integration, capacity reservation,
  quality/compliance authority, document generation, booking, dispatch,
  inventory, finance, or notification requires a separate later command with
  fresh authorization, source checks, idempotent delivery, receipts, failure
  handling, and recovery evidence.

## Consequences

Operators get a faster readiness decision without copying approved commercial
data or confusing readiness with execution. A stale, held, substituted,
cross-tenant, tampered, or unevidenced source fails closed before GO.

Version 1 deliberately treats the uploaded readiness bundle as human-reviewed
evidence. It does not claim automated carrier capacity, warehouse reservation,
quality clearance, compliance clearance, or document validity while those
authoritative modules and integrations are absent. Future checklist versions
may consume their typed current-state signals without changing version 1.

## Alternatives

- Create a shipment plan or dispatch on GO: rejected because a readiness fact
  is not execution authority and the required side-effect recovery does not yet
  exist.
- Re-enter proposal terms in a shipment form: rejected because it adds friction
  and permits an unaudited divergence from the approved source.
- Let the browser submit passed checklist items: rejected because client state
  is attacker-controlled and cannot establish policy facts.
- Require separate uploads for every future specialist signal: rejected because
  the relevant authorities are not implemented and placeholder bureaucracy
  would not improve correctness.
- Make HOLD terminal: rejected because corrected operational evidence needs a
  governed recovery path without duplicating the source case.

## Validation

- domain, command, database, API, and UI tests cover success, replay, evidence,
  exact task, GO/HOLD, HOLD resubmission, stale source, missing permission,
  tenant/source/task/evidence substitution, client checklist injection,
  one-case uniqueness, audit/outbox flags, and atomic rollback;
- database tests prove forced row-level isolation and source ownership;
- UI and runtime qualification prove the three-action, zero-term-entry workflow
  and the absence of downstream effects;
- architecture checks prove `trade.shipments` imports only declared public
  module boundaries and the product-neutral kernel remains unchanged; and
- protected delivery, exact committed and merged images, PostgreSQL/object
  storage, two-replica failover, and rendered desktop/mobile evidence remain
  mandatory before the fifth Gate 3 vertical is delivered.
