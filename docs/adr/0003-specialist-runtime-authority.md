# ADR-0003: Specialist Runtime and Authority Boundaries

**Status:** Accepted

**Date:** 2026-08-11

## Context

Existing repositories contain specialist assets whose requirements differ from
transactional ERP/CTRM processing. Combining them into one database or runtime
would duplicate authority and weaken independent security and scaling.

## Decision

- The external communications system remains the communication-content system
  of record.
- The external collaborative-canvas system remains the canvas and convergence
  system of record.
- Document-intelligence workers perform bounded extraction and model
  computation and return proposals or evidence.
- The analytics execution plane performs bounded analytical, optimization, or
  parsing work.
- A maintained back-office system may own capabilities selected by later
  domain-specific ADRs.
- UOK integrates each through typed, versioned, idempotent contracts and stores
  only its owned links, projections, policy decisions, and receipts.

Product-facing identifiers describe these business roles rather than their
current implementations. Deployment configuration binds a role to an exact
implementation only where interoperability and operations require it.

## Consequences

There is no shared database, iframe shortcut, copied communication content,
second merge engine, or model-driven bypass around UOK commands and policies.
Every adapter requires health, timeout, retry, idempotency, reconciliation,
audit, degraded-operation, and rollback behavior.
