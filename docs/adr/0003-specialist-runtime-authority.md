# ADR-0003: Specialist Runtime and Authority Boundaries

**Status:** Accepted

**Date:** 2026-08-11

## Context

Existing repositories contain specialist assets whose requirements differ from
transactional ERP/CTRM processing. Combining them into one database or runtime
would duplicate authority and weaken independent security and scaling.

## Decision

- K-Comms remains the communications system of record.
- K-Board remains the collaborative canvas/convergence system of record.
- Python workers perform bounded document/AI computation and return proposals
  or evidence.
- Rust components perform bounded collaboration, analytical, optimization, or
  parsing work.
- Odoo or another maintained back-office platform may own capabilities selected
  by later domain-specific ADRs.
- UOK integrates each through typed, versioned, idempotent contracts and stores
  only its owned links, projections, policy decisions, and receipts.

## Consequences

There is no shared database, iframe shortcut, copied communication content,
second merge engine, or model-driven bypass around UOK commands and policies.
Every adapter requires health, timeout, retry, idempotency, reconciliation,
audit, degraded-operation, and rollback behavior.

