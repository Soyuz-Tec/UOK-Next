# ADR-0024: Local user access and password activation

**Status:** Accepted

**Date:** 2026-08-26

## Context

Gate 3 has one clone-local bootstrap access code bound to a fixed tenant and
administrator actor. That proves the business journey but cannot represent
multiple attributable operators. The user-management outcome must be faster
than manually provisioning a permanent password while preserving tenant scope,
least privilege, revocation, credential secrecy, and the separation between a
human actor and a business party.

Current enterprise workflow evidence converges on administrator invitation,
bounded role assignment, user-controlled credential activation, self-service
password change, session revocation, and multifactor authentication. This
increment implements the local qualification subset without selecting a
production identity provider or delivery channel.

## Decision

- Keep the existing high-entropy access code as the local bootstrap
  administrator only. Successful authentication creates a random opaque,
  server-revocable bootstrap session whose digest and lifecycle are stored in
  PostgreSQL. The access code receives `identity:users:manage` and is never
  copied into a user record or bearer token.
- Add tenant-owned actors, password credentials, revocable sessions, and shared
  login throttles under `platform.identity`. Password authentication remains
  unavailable outside the `local_qualification` deployment profile.
- An administrator creates a pending actor with one of two allowlisted local
  access profiles and a temporary password. The password is accepted only over
  the protected API boundary, excluded from logs, stored through a versioned,
  salted, deliberately expensive password verifier, and never returned or
  stored in command/audit/event data. The initial portable verifier uses
  PBKDF2-HMAC-SHA-256 at 600,000 iterations through the OTP cryptographic
  runtime; its encoded work factor permits measured upgrades.
- A first login receives only `identity:password:change`. The actor must provide
  the temporary password again and choose a new password before any business
  permission is issued. Changing the password increments credential generation
  and revokes every prior session.
- A normal login issues a random opaque bearer secret. PostgreSQL stores only
  its SHA-256 digest, expiry, credential generation, and revocation state. Each
  request revalidates session, actor status, credential generation, tenant, and
  current access profile. Signing out revokes the stored session.
- The session-creation route accepts only `application/json`. Missing and
  malformed usernames use one shared unknown-user throttle bucket, so caller
  identifier variation cannot create unbounded rows or bypass the expensive
  verifier admission limit. Known users retain tenant-scoped per-account
  throttles.
- Usernames are case-insensitively unique inside the fixed local tenant. A
  username is a login identifier, never the stable actor identity. The actor
  UUID remains authoritative and is not a party or counterparty identifier.
- Local access profiles are deliberately bounded to party onboarding. The
  operator can create, read, and attach evidence. The reviewer additionally
  reads exact tasks and records onboarding decisions. The browser hides
  unavailable actions, while the server remains authoritative.
- Passwords accept printable passphrases of 15 to 128 Unicode code points,
  reject a bounded list of commonly compromised values, impose no composition
  rules, and allow paste and password-manager completion. Authentication uses
  uniform errors and PostgreSQL-backed throttling across application replicas.

## Consequences

The local qualifier can create multiple attributable users without sharing the
bootstrap access code. Both bootstrap and regular sessions are revoked in the
shared database before the browser clears its local copy. Creation, password
activation, sessions, audit records,
outbox events, row-level tenant isolation, and role-bounded onboarding can be
tested end to end. The administrator knows a temporary password only until the
user replaces it; no reusable user password is recoverable from the database.

This does not claim production identity. Invitation delivery, password reset,
account suspension administration, multifactor/passkey enrollment, federation,
provisioning, trusted production ingress, cookie-based browser sessions, and
identity recovery remain explicit later increments. Production continues to
fail closed without a separate identity decision.

## Alternatives

- Share the bootstrap access code: rejected because activity would not be
  attributable and revocation would affect every operator.
- Let administrators assign permanent passwords: rejected because it creates
  reusable shared knowledge and weakens non-repudiation.
- Store browser-supplied permissions: rejected because the client would become
  an authorization issuer.
- Implement production federation in the same increment: rejected because no
  production identity authority, tenant discovery, recovery policy, or trusted
  ingress has been selected.

## Validation

- positive tests for administrator creation, first login, forced password
  change, second login, session verification, party creation, and sign-out;
- negative tests for invalid credentials, duplicate usernames, weak passwords,
  unauthorized user creation, permission escalation, cross-tenant access,
  credential-generation mismatch, expired/revoked sessions, exact bootstrap
  token replay after sign-out, non-JSON login, and distinct-username throttling;
- database checks for tenant composite references, row-level security, token
  digest length, credential generation, username uniqueness, and bounded state;
- frontend tests for regular/bootstrap login, password activation, user
  creation, permission-aware party controls, and keyboard-accessible feedback;
- formatter, compiler, static analysis, dependency advisory, architecture,
  security diff, immutable release, and exact-revision runtime qualification.
