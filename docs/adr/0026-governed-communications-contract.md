# ADR-0026: Governed communications links and delivery intents

**Status:** Accepted for local contract qualification; live integration deferred

**Date:** 2026-09-05

## Outcome and scope

The first Gate 4 increment connects one exact party version to an externally
owned conversation using opaque identifiers. It records a recoverable intent
to hand that business-object link to the communications system. It adds no
message composer, message replica, membership administration, call transport,
attachment storage, or business execution.

The continuity requirement in ADR-0027 remains broader. This bounded contract
is prerequisite infrastructure; it does not qualify legacy messaging, calls,
threads, notifications, evidence promotion, or communication-to-task parity.

## Decision

- `platform.integrations` owns immutable `communication_link` records and
  existing `integration_receipt` records. A link binds tenant, party identity,
  exact party version, conversation UUID, creator, and creation time. The
  module declares a public-query dependency on `master.parties`.
- Link creation, retrieval, delivery, and reconciliation require named
  `communications:*` permissions. Every subject operation resolves the current
  party through its public API with the caller's context and exact version.
  A stored link cannot grant access or make a stale subject authoritative.
- A separate communications port independently authorizes the exact tenant,
  actor, conversation, operation, and canonical request digest. Its proof is
  bounded, short-lived, and never accepted from the HTTP caller. Authorization
  is repeated before cached command results can be returned and before adapter
  delivery or reconciliation. UOK permissions do not grant external membership.
- Strict allowlists reject unknown request, authorization, health, and receipt
  fields. Envelopes contain identifiers and a server-derived SHA-256 only;
  no body, recipient list, credentials, URL, participant projection, or raw
  provider response is stored. The role is fixed to `communications_system`.
- A delivery intent uses the existing connector attempt primitive. The durable
  attempt commits before the adapter can act. Delivery rejects an enclosing
  application transaction and rechecks its server deadline after authorization.
  Command, audit, and outbox state
  remain atomic; transport does not participate in a database transaction.
  Stable delivery identity and request digest survive retries. A new attempt
  must descend from a matching failed or timed-out receipt.
- Reconciliation is a separately authorized command bound to the link,
  receipt, and expected receipt version. A validated `contract_accepted`
  acknowledgement proves only that this contract was accepted by the double.
  External message delivery and read state remain unverified. A transport
  interruption leaves durable evidence for reconciliation; it never becomes
  success merely because a command was accepted locally.
- The generic receipt public API reserves `communications_system` for this
  boundary, preventing generic permissions or caller-supplied outcome data
  from forging a communications acknowledgement.
- Health is a bounded, permission-protected query. Unavailable, denied,
  malformed, or expired external authority fails closed. Health alone grants
  no subject access or delivery authority.
- Deployment defaults to a disabled adapter. The test-only contract double
  has independent grants, revocation, idempotent acceptance, and failure
  controls. Production verification requires the adapter to remain disabled.
  No credentials or live provider selection are introduced.

## Migration and recovery

The additive migration creates only the integration-owned link table with
forced tenant RLS, positive-version constraints, and tenant-scoped uniqueness.
Application grants allow link insertion and reading, with no update or delete
authority. Readiness requires the new migration. No legacy data is copied.

Roll out through normal protected delivery: migrate, reconcile exact database
grants, deploy the new release, and verify readiness. The disabled default
keeps external effects closed. Review the local-double qualification receipt
before any later adapter selection.

On interruption after an attempted handoff, query the communications system
through the reconciliation command using the same link and receipt identity.
Do not create a new delivery key to work around uncertainty. Retry only through
the recorded lineage after the server has classified a recoverable outcome.
Keep accepted and unresolved receipts for attributable incident review.

The initial request digest binds the initiating actor and exact party version.
Reconciliation requires that actor to retain both permissions and external
membership and the party version to remain current. Actor revocation or party
evolution therefore blocks ordinary recovery; no administrator override is
implied. Delegated incident closure and historical-subject authorization need
a separate reviewed policy before live activation.

Rollback deploys the previous release while retaining the additive link table
and receipts. Remove newly granted link privileges using the previous grant
reconciliation script. Do not run the destructive migration down after creating
records; governed retention/export must precede eventual table retirement.

## Threat model and validation

An authenticated operator may alter identifiers, versions, idempotency keys,
or JSON fields. A compromised or defective adapter may return a forged,
oversized, substituted, stale, or malformed acknowledgement. Neither source
may grant itself UOK permission or external conversation membership.

Required executable cases cover missing permissions, foreign tenants, stale
subjects, revocation before replay, conflicting idempotency, concurrent
attempts, exact receipt binding, bounded adapter failures, timeout/recovery,
RLS, database constraints, and atomic audit/outbox evidence. The HTTP contract
also checks authentication and request metadata. Full repository quality,
advisory, production-configuration, and immutable release checks remain gates.

Local-double evidence does not establish a real external transaction, replica
failover, production identity, migration completeness, or disaster recovery.
Gate 4 remains active until those applicable contracts and operational proofs
are completed in bounded increments.

## Technical provenance and compatibility gap

The pinned prior communications application at revision
`112aac9cfcf6459dbd5a351434d86d7492c7113b` supplies the reference control
pattern: independently authenticate service scope and current conversation
membership even when replaying an idempotent request. Its service-message API
uses an 8–128 character idempotency key and forbids service attachments.

- [Source API contract](https://github.com/Soyuz-Tec/k-comms/blob/112aac9cfcf6459dbd5a351434d86d7492c7113b/contracts/openapi/openapi.yaml)
- [Transactional service authorization](https://github.com/Soyuz-Tec/k-comms/blob/112aac9cfcf6459dbd5a351434d86d7492c7113b/apps/comms_core/lib/comms_core/messaging/service_messages.ex)
- [Independent membership policy](https://github.com/Soyuz-Tec/k-comms/blob/112aac9cfcf6459dbd5a351434d86d7492c7113b/apps/comms_core/lib/comms_core/conversations/access_policy.ex)

That source API does not define the typed UOK business-object-link contract
implemented here. Provider interoperability requires a separately reviewed
adapter or compatible provider endpoint and explicit identity mapping. It
cannot be inferred from matching UUIDs or the double's acknowledgement.
