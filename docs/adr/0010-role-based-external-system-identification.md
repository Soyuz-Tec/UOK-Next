# ADR-0010: Role-based external-system identification

**Status:** Accepted

**Date:** 2026-08-11

## Context

External company and product identities in application code, public contracts,
catalogs, UI, examples, and general architecture couple durable UOK concepts to
replaceable implementations. They also disclose selections that are irrelevant
to a user's business intent and encourage provider-specific fields to leak into
domain records.

Complete anonymity is unsafe in dependency, licensing, security, and operations
evidence: a build artifact, advisory, software bill of materials, protocol
binding, or operator procedure cannot be verified when the implementation is
unidentifiable. The boundary therefore needs to distinguish product-facing
identity from technical provenance.

## Decision

- Product-facing code, APIs, events, catalogs, UI, fixtures, examples, diagrams,
  assessments, and documentation identify external systems by stable business
  role. Company, product, account, and tenant-specific implementation names are
  excluded.
- UOK's initial external roles are communications system, collaborative-canvas
  system, document-intelligence workers, analytics execution plane, selected
  back-office system, and evidence-anchor system. Their machine identifiers and
  display names are governed by `config/external_identity_policy.json`.
- Deployment configuration may bind a role to an exact implementation behind a
  typed anti-corruption adapter. A binding cannot change record ownership,
  permissions, commands, events, user-interface labels, or domain identifiers.
- Exact implementation identities are allowed only where they are required to
  reproduce a dependency or build, preserve license/attribution, investigate a
  vulnerability, prove artifact provenance, configure interoperability,
  operate a deployment, or record an implementation-selection decision.
- Required exact identities are minimized and never used as business payload,
  log, screenshot, fixture, example, or competitive-comparison content.
- Organization and counterparty names entered as governed business records are
  not implementation identities. They remain protected by tenant, privacy,
  authorization, retention, and audit policy.
- The foundation verifier fails closed when the module catalog uses an
  unapproved external role, mismatched role label, non-role identity class, or
  any field outside the governed external-role schema.

## Consequences

Public contracts remain stable when implementations change, integration logic
stays behind explicit adapters, and general UOK material avoids unnecessary
third-party identification. Technical evidence remains precise enough for
secure builds, legal compliance, incident response, and repeatable operations.
Adding an external role or changing an approved label requires a reviewed
policy update and an ownership assessment.

## Alternatives

- Remove every exact technical identity: rejected because builds, licenses,
  vulnerability response, artifact verification, and operations would become
  unverifiable.
- Use implementation names throughout the repository: rejected because it
  couples business contracts to replaceable systems and expands disclosure.
- Keep the rule only in prose: rejected because catalog drift would not fail
  CI.

## Validation

- Foundation verification compares every external-system catalog entry with
  the approved role policy and rejects any unapproved field.
- Repository review confirms product-facing architecture, ownership, roadmap,
  continuity, and historical boundary decisions use role-based identities.
- Dependency, license, security, and operational evidence retains the minimum
  exact identity needed for verification.
