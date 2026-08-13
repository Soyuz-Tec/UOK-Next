# ADR-0020: Source-bound purchase-commitment proposal

**Status:** Accepted

**Date:** 2026-08-13

## Context

The delivered sourcing vertical produces an attributable, deterministic, and
human-approved quote-comparison snapshot. The next Gate 3 handoff must let a
buyer propose the commercial commitment without re-keying supplier, quantity,
price, currency, delivery, product, route, or source evidence. It must also
prevent an approved comparison from silently becoming a contract, order,
payment instruction, inventory movement, or supplier communication.

Current successful enterprise procurement workflows consistently preserve a
source document, explicit approval state, material attachments, decision
history, versioned changes, and a separate downstream issuance step. Their
common friction is repeated document transfer and late discovery of stale or
changed source terms. UOK adopts the controls while replacing the transfer
with one server-derived proposal and fresh source validation at every
consequential transition.

## Decision

- `trade.contracts` owns `purchase_commitment_proposal`. A proposal is an
  internal, non-binding request to approve the exact recommended offer from one
  approved `trade.sourcing` comparison. It is not a purchase contract, purchase
  order, supplier award, payment instruction, or external message.
- Creating a proposal accepts only a stable identifier, the comparison
  identifier and exact approved comparison version, and an attributable
  reason. The server obtains all commercial and lineage fields through the
  public `trade.sourcing` contract; the browser, a model, or an integration
  cannot submit supplier, price, quantity, currency, delivery, product, route,
  or recommendation fields.
- The sourcing public contract locks and revalidates the comparison, RFQ,
  requisition, and recommended quote in a stable order. It requires the current
  comparison to be approved at the expected version, the RFQ to remain
  compared, the quote to remain submitted at the snapshot version, and the
  material quote terms to match formula version 1's immutable ranking row.
- The proposal stores a bounded immutable source snapshot containing only the
  identifiers, source versions, governed commercial terms, evidence digest,
  required date, and formula version needed for review and recovery. One
  comparison can create at most one proposal.
- Proposal creation produces a `draft`; it opens no review task. Verified
  evidence must be stored through `platform.evidence` against that exact
  proposal. Evidence submission revalidates the source, changes the proposal
  to `awaiting_review`, and atomically opens one exact-version human task.
- Approval revalidates the source again before consuming the exact human task.
  HOLD remains available even when a source has become invalid so reviewers can
  close unsafe work rather than leave an unresolvable task open. Both decisions
  atomically record proposal state, actor, reason, command receipt, append-only
  audit evidence, and outbox events. The response explicitly records
  `commitment_created: false` and `external_effect_created: false`.
- PostgreSQL enforces composite tenant references, the selected quote's
  relationship to the source comparison, one proposal per comparison, forced
  row-level security, lifecycle completeness, bounded snapshots, optimistic
  concurrency, and positive source versions.
- The initial UI is a single review workspace. Selecting an approved
  comparison pre-fills the proposal through the server, then exposes evidence
  and decision actions against the latest returned version. It displays the
  source chain and material terms together so a reviewer does not navigate
  across replicated documents.
- Any later contract, order, supplier acknowledgment, connector dispatch,
  payment, or inventory action requires a separate typed command, fresh
  authorization and source validation, its own ownership decision, and
  recovery evidence. Approval of this proposal is never reusable bearer
  authority for that action.

## Consequences

The workflow is faster because users do not copy approved quote data into a
second document, yet every material field remains explainable from an exact
source version. A stale, held, substituted, cross-tenant, or tampered source
fails closed before evidence submission or decision.

This slice intentionally excludes negotiated edits, partial awards, split
awards, alternate quantities, tax and freight enrichment, multi-currency
normalization, accounting distributions, legal clauses, signatures, supplier
acknowledgment, and contract/order creation. Each changes the authority or
commercial meaning and needs an explicit later version rather than hidden
proposal overrides.

## Alternatives

- Create a contract directly from comparison approval: rejected because an
  internal sourcing decision is not legal or operational commitment authority.
- Let users re-enter or edit winning terms: rejected because it adds friction
  and creates an unaudited divergence from the approved comparison.
- Store only a comparison identifier: rejected because review, recovery, and
  later reconciliation require a bounded explainable snapshot of the exact
  terms considered.
- Open the approval task at proposal creation: rejected because a reviewer must
  not approve a material proposal before its governed evidence is verified.
- Communicate the approved proposal to the supplier automatically: rejected
  because external delivery has distinct authorization, idempotency, receipt,
  retry, acknowledgment, and recovery requirements.

## Validation

- domain, command, database, API, and UI tests cover success, replay, evidence,
  exact task, approve/HOLD, stale state, changed source, missing permission,
  tenant substitution, source and task substitution, one-proposal uniqueness,
  tampered client terms, and atomic rollback;
- the response, audit, events, and database prove that no contract, connector
  attempt, payment, inventory movement, or other external effect is created;
- architecture verification proves `trade.contracts` imports only declared
  public module boundaries and the kernel remains product-neutral; and
- protected delivery, an exact merged-revision image, PostgreSQL/object-store
  qualification, two-replica failover, and rendered desktop/mobile proof remain
  mandatory before this Gate 3 increment is delivered.
