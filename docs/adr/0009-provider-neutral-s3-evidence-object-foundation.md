# ADR-0009: Provider-neutral S3 evidence-object foundation

**Status:** Accepted for local and CI qualification; production provider deferred

**Date:** 2026-08-11

## Context

Gate 1 requires a reproducible local object-storage dependency and a bounded
evidence-object contract. The storage system must hold bytes without becoming
the authority for tenant scope, policy, review state, retention, audit, or
business transitions. The application must also avoid binding its contract to
one self-hosted product.

MinIO's upstream repository was archived in April 2026 and its current
community distribution no longer provides a suitable maintained container
baseline. RustFS remains prerelease and has recently changed security-critical
defaults. SeaweedFS 4.37 is actively maintained, Apache-2.0 licensed, exposes
an S3-compatible API, and documents `weed mini` specifically for development
and small local qualification environments.

## Decision

- UOK code depends on a narrow S3-compatible application port, not on
  SeaweedFS-specific APIs. SeaweedFS 4.37 is the digest-pinned local and CI
  qualifier only; no production storage provider is selected by this ADR.
- The local store runs as UID/GID `10001:10001`, with a read-only root
  filesystem, dropped capabilities, bounded CPU/memory/processes, persistent
  data volume, loopback-only host exposure, and fresh credentials for every
  qualification run. Unused browser/admin/WebDAV/IAM surfaces are disabled or
  not exposed.
- Production configuration requires HTTPS. The local qualification profile may
  use HTTP only to the fixed `object-store` compose peer on its isolated
  network. Endpoint URLs reject credentials, query strings, fragments, and
  arbitrary local hosts.
- An evidence candidate is limited to 8 MiB initially, uses an allowlisted
  media type, starts in `quarantined`, and receives a server-derived key from
  validated tenant/evidence UUIDs plus its SHA-256 digest. Callers never submit
  a path or bucket.
- Uploads use create-only semantics and must pass read-after-write byte-count
  and SHA-256 verification. Storage errors are normalized and never expose
  credentials or provider response bodies.
- S3 control-operation responses are streamed through a 64 KiB fail-closed
  collector. The declared 8 MiB candidate ceiling is also the runtime and
  domain hard limit; operator configuration cannot raise it.
- Read-back uses a server-internal S3 Signature V4 URL with a 60-second
  lifetime, rejects redirects, halts if the response exceeds the HEAD-declared
  byte count, and never returns that URL to a browser or caller.
- PostgreSQL remains authoritative for evidence metadata, classification,
  policy, review state, retention, audit, deletion intent, and integration
  receipts. Object-store lifecycle or object-lock behavior is not accepted as
  business-policy enforcement.
- Gate 1 exposes no browser upload and no unaudited business command. Gate 2
  will add authorized, tenant-scoped, idempotent, audited commands and durable
  external-effect receipts before evidence objects become a product feature.

## Consequences

The complete local dependency topology now includes PostgreSQL and an actual
S3-compatible object store while the application boundary remains portable.
The qualifier proves a real put/read/verify/delete round trip, container
identity, and continued application failover. This does not prove production
durability, encryption/KMS, replication, backup/restore, legal hold, malware
scanning, lifecycle, or disaster recovery.

## Alternatives considered

- MinIO Community Edition: rejected because the upstream repository is
  archived and the maintained container/update path no longer fits the
  foundation's supply-chain requirements.
- RustFS: deferred because the available release is still beta and recent
  security changes show that its operational contract is still moving.
- SeaweedFS as a production selection: rejected by scope; production storage
  requires measured durability, support, encryption, recovery, observability,
  cost, and data-residency evidence in Gate 7.
- Filesystem-only test adapter: rejected because it would not prove the
  provider-neutral S3 boundary or real dependency topology.
- Browser-direct presigned uploads in Gate 1: deferred until identity,
  authorization, policy, audit, expiry, content validation, and quarantine are
  executable in Gate 2.

## Validation

- machine checks for image identity, local-only exposure, non-root execution,
  bounded resources, production HTTPS, credential separation, and absence of
  secrets in browser code;
- domain and contract tests for identity, size, type, server-derived keys,
  integrity, storage receipts, tampering, and deletion;
- CI and local runtime S3 put/collision-rejection/read/verify/delete
  qualification;
- immutable release build, two-replica readiness/release identity, and
  single-replica failover with the object store present;
- dependency/advisory audits and a diff-scoped Codex Security assessment.
