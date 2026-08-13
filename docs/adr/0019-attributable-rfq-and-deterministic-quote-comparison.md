# ADR-0019: Attributable RFQ and deterministic quote comparison

**Status:** Accepted

**Date:** 2026-08-12

## Context

The first two Gate 3 verticals proved approved parties and evidence-backed
sourcing lanes. The proving operation now needs a commercial solicitation
boundary that preserves exact source versions, supplier attribution, verified
quote evidence, deterministic comparison, and human authority. A generic CRUD
model or opaque scoring service would weaken those guarantees and provide no
reliable oracle for later advisory automation.

Purchase commitment is a separate consequential boundary. Comparing quotes
must not itself create a contract, payment, inventory movement, or external
side effect.

## Decision

- `trade.sourcing` owns purchase requisitions, RFQs, RFQ supplier invitations,
  supplier quotes, and quote comparisons. These records use the existing
  command, tenant, audit, outbox, evidence, and human-task primitives.
- A requisition binds the exact approved sourcing-lane version, positive
  quantity, governed unit, and required date. Its unit must match the active
  product authority reached through the lane.
- Opening an RFQ consumes the exact ready requisition version, records one
  settlement currency and future response deadline, and invites between two
  and twenty distinct same-tenant approved suppliers. Each invitation records
  the approved Party version used at invitation time.
- One invited supplier may have one quote in an RFQ. The quote quantity must
  equal the requisition quantity, its currency must equal the RFQ settlement
  currency, and its price and delivery term are bounded positive values.
- A quote remains a draft until a verified evidence object bound to that exact
  quote is submitted. Evidence metadata stores only the governed identifier,
  digest, and classification; source bytes remain owned by
  `platform.evidence` and object storage.
- Closing an RFQ for comparison requires at least two submitted quotes. Before
  the response deadline, every invited supplier must have submitted; after the
  deadline, the two-submission floor applies. The check and close share the RFQ
  row lock so an early comparison cannot silently exclude a still-eligible
  response. The server creates an immutable versioned snapshot ordered by
  total price, then delivery days, then stable quote identifier. Formula
  version 1 recommends the first row; the browser, a model, or an integration
  cannot provide or alter the recommendation.
- Creating a comparison changes the RFQ to `comparison_pending` and opens one
  exact version-bound human task. Approve or HOLD consumes that task in the
  same transaction as comparison and RFQ state, command receipt, audit, and
  outbox events.
- Approval records acceptance of the comparison only. No purchase commitment,
  contract, connector attempt, job, payment, or settlement command is created.
  A later `trade.contracts` vertical must reauthorize any commitment against
  current state and its own evidence and approval policy.
- PostgreSQL composite tenant foreign keys, forced row-level security,
  lifecycle constraints, uniqueness, decimals, optimistic locks, and exact
  version bindings reinforce application policy. New permissions remain
  command-specific and server-owned.

## Consequences

The system gains a deterministic business oracle suitable for audited human
decisions and later advisory AI evaluation without granting AI authority. The
snapshot preserves the material offer terms and source versions needed to
explain why a recommendation was produced.

The first formula deliberately compares same-currency, equal-quantity offers
only. Taxes, quality premiums, freight, financing, risk, alternate quantities,
multi-currency normalization, revisions, withdrawals, negotiation, partial
awards, and weighted policy factors require explicit later versions rather
than hidden changes to formula version 1.

## Alternatives

- Let users or a model choose the recommended quote: rejected because the
  comparison would not be deterministic, reproducible, or independently
  testable.
- Accept quote JSON without evidence: rejected because supplier attribution
  and material terms would lack governed source evidence.
- Create a purchase commitment when comparison is approved: rejected because
  commitment is a separate ownership, policy, and recovery boundary.
- Store copied supplier, product, or lane descriptions: rejected because that
  creates shadow master data and ambiguous correction authority.
- Use one mutable RFQ document containing embedded quotes: rejected because it
  obscures attribution, concurrency, evidence lifecycle, and exact versions.

## Validation

- domain, command, database, and API tests cover successful flow, replay,
  validation, missing permission, tenant substitution, non-invited supplier,
  insufficient submitted quotes, rejection of premature close with an
  outstanding invitation, stale state, exact task, evidence binding,
  deterministic ranking, and atomic rollback;
- UI tests and rendered desktop/mobile proof exercise the real APIs without
  browser-owned policy;
- OpenAPI, architecture, code discipline, database, object-store, static
  security, advisory, immutable release, and exact-revision qualification
  remain required delivery gates; and
- `docs/STATUS.md` distinguishes candidate evidence from protected-main and
  deployed qualification evidence.
