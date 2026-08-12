# ADR-0014: Gate 3 party-onboarding vertical

**Status:** Accepted

**Date:** 2026-08-12

## Context

Gate 2 proved the internal party commands, evidence-byte port, human-task
primitive, audit records, and outbox records independently. Gate 3 requires a
real user journey through the browser and versioned API. The previous shell had
no authenticated business surface, evidence submission accepted metadata that
was not linked to persisted object metadata, and a storage failure between a
database command and object upload had no explicit retry path.

The production identity provider and deployment platform are intentionally not
selected. A local demonstration must not create an identity or plaintext
transport fallback that can activate in another deployment profile.

## Decision

- Deliver party onboarding as the first bounded Gate 3 vertical before adding
  product, sourcing, contract, shipment, or reporting contexts.
- The isolated local qualifier issues an eight-hour signed bearer token only
  after constant-time verification of a high-entropy, clone-local access code.
  Tenant, actor, and fixed permissions come exclusively from protected server
  configuration. Clients never submit tenant or permission claims. The adapter
  is absent in production and is not a production identity selection.
- Publish the versioned API under `/api/v1` with a machine-readable contract.
  Mutations require a bounded `Idempotency-Key`; server-created correlation
  identity, named permissions, optimistic concurrency, and forced row-level
  security remain authoritative.
- Persist evidence metadata as a `platform.evidence` record before object-store
  work only after a server-owned party preflight proves permission,
  tenant-scoped existence, lifecycle eligibility, and expected version. Store
  content at a server-derived immutable key, verify exact length and SHA-256 by
  read-after-write, then finalize the metadata in a second command. Both
  commands are independently idempotent and audited. The final party command
  repeats validation under a row lock so a preflight race fails closed.
- A retry encountering already stored bytes reads and verifies them rather than
  overwriting or deleting them. A crash before finalization leaves a durable
  `pending_upload` record that the same request can recover. The database keeps
  only a bounded digest of the storage receipt, not raw remote content or
  credentials.
- Qualification receipts expose only the ACL-protected credential path and
  non-secret identity metadata. They never emit the reusable access code.
- Multipart paths are accepted only through server-created `Plug.Upload`
  structs and must resolve to bounded regular files. The narrowly documented
  static-analysis suppression covers that framework-generated path only;
  unsuppressed security findings fail the quality command.
- `master.parties.submit_evidence` accepts only an evidence identifier that
  `platform.evidence` confirms is verified, tenant-matched, and bound to the
  exact party. It then opens the exact review task atomically with party state,
  audit evidence, outbox events, and the command receipt.
- Expose only open tasks whose recorded permission is held by the authenticated
  actor. Approval or hold continues to consume the exact subject/version-bound
  task in the party command transaction.
- Keep the React shell presentation-only. The party workspace lives under the
  owning module UI; the application entrypoint composes it without introducing
  browser-side authorization or transition policy.

## Consequences

The local application now supports a real create, upload, review, and decision
journey with recoverable object work and attributable database state. Browser
state contains a short-lived signed token in session storage; the access code
is never stored there. The clone-local identity remains stable across
qualification rebuilds so existing local tenant data remains accessible.

This vertical does not provide production OIDC, session revocation, malware
scanning, evidence retention/deletion workflows, general task assignment or
escalation, outbox delivery, or the remaining proving-operation stages. Gate 3
therefore remains active after this vertical is qualified.

## Alternatives

- Trust tenant, actor, or permission headers: rejected because the browser
  would become an authorization issuer.
- Embed a fixed demonstration password in source: rejected because every clone
  would share a credential and rotation would require a release.
- Store object bytes before any database record: rejected because a crash can
  create an unowned object with no deterministic recovery identity.
- Delete an existing immutable object when a retry collides: rejected because
  a retry could destroy verified evidence from an earlier successful attempt.
- Add all remaining Gate 3 business contexts in the same increment: rejected
  because the active party journey must first prove API, identity, evidence,
  workflow, UI, and recovery boundaries end to end.

## Validation

- positive browser/API tests for sign-in, draft creation, real evidence upload,
  task visibility, approval, final read, audit/outbox counts, and replay;
- negative tests for invalid authentication, missing permission, tenant and
  subject substitution, stale state, unsupported content, missing/oversized
  upload, forged token, and production-profile activation;
- recovery test for a retry after bytes were stored but metadata finalization
  had not completed;
- negative tests proving unknown and stale party submissions persist neither
  evidence metadata nor object bytes, and replay verification never deletes a
  pre-existing object after a transient read failure;
- forced row-level-security and tenant-referential checks for the evidence table;
- format, compile, static analysis, security, architecture, database, frontend,
  immutable release, rendered desktop/mobile, and exact-revision runtime checks.
