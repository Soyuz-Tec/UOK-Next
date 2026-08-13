# ADR-0016: Security-scan artifact-sealing waiver

**Status:** Accepted

**Date:** 2026-08-12

## Context

The product, location, and sourcing-lane increment received two independent
repository security reviews. The first review produced a sealed report and
identified one low-severity lifecycle defect. That defect was corrected and
regression-tested. The final immutable revision-range review then inspected all
50 changed files, deferred none, and reported no finding. Its report finalizer
could not seal the otherwise complete review because the revision-range target
did not provide the snapshot-digest metadata expected by the finalizer.

Repeating the same review cannot supply metadata that the scan adapter does not
produce. The product owner explicitly authorized continuation past this
artifact-sealing failure on 2026-08-12. The authorization does not waive source
review, tests, static security analysis, dependency audits, protected CI,
required review, exact-revision qualification, or deployment controls.

## Decision

- Waive only the missing canonical sealed report for the final post-fix
  revision-range review of this sourcing-lane increment.
- Preserve the complete 50-of-50 file coverage receipt and zero-finding result
  as local qualification evidence. Do not describe the unsealed report as a
  canonical scan artifact.
- Continue to require every repository-owned application, static-security,
  dependency, architecture, database, artifact-integrity, runtime, protected
  CI, review, and release gate.
- Do not reuse this waiver for another revision, increment, or different scan
  failure. A future security review must seal normally unless a new explicit
  decision documents its own evidence and residual risk.
- Remove the tooling limitation when the revision-range adapter and finalizer
  agree on required target metadata; this does not require a product contract
  change.

## Consequences

Delivery can continue without treating a scan-adapter metadata mismatch as a
source-code defect. The residual risk is that the corrected revision has no
canonical sealed post-fix scan bundle, even though complete file coverage and
the zero-finding result were obtained. Protected delivery evidence and the
first sealed pre-fix review remain independently inspectable.

No authentication, authorization, tenant isolation, evidence integrity,
dependency, runtime, or release safeguard is weakened by this decision.

## Alternatives

- Stop delivery indefinitely: rejected because repeated scans cannot repair
  the missing target metadata and all changed files were already reviewed.
- Mark the failed finalization as a successful sealed scan: rejected because
  that would overstate the available evidence.
- Waive all remaining security or delivery controls: rejected because the
  failure is isolated to report sealing, not implementation quality.

## Validation

- the immutable revision-range inventory records 50 reviewed files out of 50,
  zero deferred files, and zero findings;
- the validated lifecycle defect from the earlier sealed review has an
  executable regression test;
- repository static security, dependency, secret, artifact-integrity,
  architecture, database, application, and frontend checks pass;
- protected CI and review complete without bypass; and
- the exact merged revision passes the supported local qualification command.
