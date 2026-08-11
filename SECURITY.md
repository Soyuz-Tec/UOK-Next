# Security Policy

## Supported code

UOK Next is pre-release software. Only the current protected `main` revision
and an explicitly named release candidate receive security fixes. Prototype,
spike, local-qualification, and historical revisions are not production
services, but vulnerabilities that could enter a supported build are in scope.

## Report a vulnerability privately

Use [GitHub private vulnerability reporting](https://github.com/Soyuz-Tec/UOK-Next/security/advisories/new).
Do not open a public issue or include secrets, personal data, credentials, or
production records in a report. Include the affected revision, reachable entry
point, prerequisites, impact, minimal reproduction, and suggested mitigation
when known.

Maintainers will acknowledge a report, validate it against the current source,
coordinate remediation and disclosure, and publish an advisory when the issue
affects users. No response-time promise exists before the project has an
on-call rotation and funded service objective.

## Security invariants

Reviews and changes must preserve these controls:

- authentication establishes tenant, actor, and granted permissions; clients
  cannot self-issue a `CommandContext`;
- every business read and mutation is tenant-scoped in application queries and
  by forced PostgreSQL row-level security under a non-superuser,
  non-`BYPASSRLS` runtime role;
- consequential actions require named permissions and server-side policy;
- business mutation, idempotency receipt, audit evidence, and outbox events
  commit or roll back together;
- audit events are append-only to the runtime role;
- production request bodies, identifiers, headers, timeouts, and resource use
  are bounded at trust boundaries;
- secrets never enter source, logs, images, command receipts, audit metadata,
  or client responses;
- production transport, origin/proxy trust, dependencies, and release identity
  fail closed; local qualification exceptions cannot become production
  defaults;
- build and deployment inputs are hash- or digest-pinned, run with least
  privilege, and preserve required CI, review, recovery, and rollback gates.

## Current scope limits

The repository does not yet expose a production business API and the local
Podman topology is not production. Missing future functionality is not itself
a vulnerability. A report is in scope when current source creates a realistic
boundary crossing, data exposure, integrity loss, privilege gain, availability
impact, supply-chain compromise, or a control that would silently carry into a
supported deployment.

Security testing must use systems and data the reporter is authorized to test.
Denial-of-service testing, social engineering, credential attacks, and access
to another tenant's data require prior written authorization.
