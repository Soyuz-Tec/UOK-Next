# ADR-0004: Blockchain Is an Optional Evidence Anchor

**Status:** Accepted

**Date:** 2026-08-11

## Context

The existing chain prototype repository is an unchanged upstream fork and does
not implement a UOK business capability. Running a chain would add consensus,
sequencing, bridge, key, availability, privacy, cost, licensing, and operational
responsibilities unrelated to the first business outcomes.

## Decision

The kernel, workflows, identity, permissions, evidence metadata, documents, and
audit events remain off-chain. After the off-chain evidence system is
production-proven, UOK may submit periodic evidence Merkle roots through a
chain-neutral asynchronous adapter.

Only schema version, root, and the minimum non-sensitive verification metadata
may be submitted. PostgreSQL retains chain, transaction, block, confirmation,
reorganization, retry, and reconciliation receipts. Chain unavailability never
blocks business operations.

## Consequences

Anchoring may prove integrity and approximate existence time; it does not prove
the truth, legality, or authority of the underlying evidence. Smart settlement,
payments, custody, tokenization, and autonomous contract enforcement require
separate legal, security, financial, and operational decisions.
