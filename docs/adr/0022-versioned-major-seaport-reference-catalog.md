# ADR-0022: Versioned major-seaport reference catalog

**Status:** Accepted

**Date:** 2026-08-13

## Context

Origin and destination entry in the sourcing workspace required operators to
retype country, port name, and a permanent identifier. Those fields are public
standard reference information, so re-entry adds avoidable time and typo risk.
Copying every world port into every tenant would instead create unused
operational records, unclear lifecycle authority, and unnecessary database
growth.

The browser cannot become a hidden reference authority. The source catalog can
change independently, so selection also needs reproducible provenance,
deterministic refresh, a visible version, and failure behavior that does not
block a legitimate exceptional location.

## Decision

- `master.locations` owns `major_seaport_reference` as versioned, read-only
  reference data. Tenant-owned `location` remains the only operational route
  authority used by sourcing lanes.
- A repository update command retrieves an official public maritime-port
  catalog, verifies the expected schema and minimum population, and retains
  records with a standardized maritime location code. Exact source identity is
  confined to the technical provenance receipt and update command required for
  reproducibility.
- Duplicate standardized codes are resolved deterministically by harbor scale,
  catalog number, and name. Country results are ordered with larger harbors
  first and then by name; classification is guidance, not route-validity or
  safety policy.
- The immutable snapshot contains only the fields needed for selection:
  standardized code, country code and name, port name, harbor scale, and public
  catalog number. A companion receipt records source and snapshot digests,
  retrieval time, selection and ranking rules, record count, country count, and
  catalog version. Compilation fails if the snapshot digest or count differs.
- Authenticated country and country-filtered port queries reuse
  `locations:read`. They are bounded by the embedded snapshot and inherit the
  API's `no-store` response policy. No runtime request is made to an external
  service.
- Selecting a catalog port pre-fills the standard code, country, type, and
  name. The existing attributable, idempotent `locations:create` command is the
  only way to promote it into a tenant. Existing tenant codes are detected
  before submission and database uniqueness remains authoritative under races.
- A manual-exception path preserves support for valid absent locations and
  non-port route references. It uses the same validation, authorization,
  tenant, audit, outbox, and rollback behavior.
- This catalog does not establish berth, terminal, vessel, navigation, customs,
  sanctions, route feasibility, or shipment-readiness facts. Those require
  separately governed current evidence and business decisions.

## Consequences

The normal route-location workflow becomes two selections and one create
action with no identifier re-entry. Tenant tables contain only ports actually
used by that tenant. The product can work while disconnected from the upstream
publisher, and a catalog refresh is reviewable as an explicit repository diff.

The snapshot adds repository size and needs a scheduled maintenance decision
before automatic updates are introduced. A standard code can still be retired
or corrected upstream; operational location lifecycle and migration commands
remain future work rather than being changed silently by a catalog refresh.

## Alternatives

- Store the catalog only in browser code: rejected because presentation would
  become an ungoverned reference authority with no server contract.
- Insert every port for every tenant: rejected because it creates unused
  operational records and ambiguous lifecycle semantics.
- Query an external service on every country change: rejected because latency,
  availability, privacy, and unreviewed upstream changes would enter the
  operational path.
- Allow only catalog ports: rejected because legitimate new, private, or
  exceptional locations must not be blocked by reference publication timing.

## Validation

- catalog tests verify digest, count, unique standardized codes, country
  indexing, known representative ports, deterministic ordering, and malformed
  country rejection;
- API tests cover authentication, named permission, response security policy,
  country filtering, and validation failure;
- UI tests cover country selection, port loading and prefill, duplicate
  prevention, manual fallback, retained values on failed create, and success;
- architecture, format, compiler, static analysis, dependency, security diff,
  build, rendered desktop/mobile, and exact-revision runtime checks remain
  delivery gates.
