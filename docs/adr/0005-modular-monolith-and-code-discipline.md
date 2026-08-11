# ADR-0005: Modular Monolith and Code Discipline

**Status:** Accepted

**Date:** 2026-08-11

## Context

The greenfield platform needs strong internal boundaries without paying the
early consistency, deployment, observability, and operating cost of a service
network. It also needs source-size discipline without encouraging small files
that obscure one cohesive business concept.

## Decision

Use one Phoenix/Mix application, one PostgreSQL database, one React workspace,
and one application release. Organize code by bounded context with product-
neutral kernel primitives, module public APIs, acyclic declared dependencies,
private data ownership, transactional commands, outbox events, and explicit
workflow coordination.

Adopt the review and maximum thresholds in `docs/ENGINEERING_STANDARDS.md` and
`config/code_policy.json`. Maximum file thresholds are machine-enforced;
exceptions require owner, reason, expiry, and replacement plan. Function size,
complexity, nesting, warnings, and boundary imports become static checks during
the Gate 1 executable scaffold.

## Consequences

- Most business changes can remain transactional and locally testable.
- Module contracts remain extraction seams without pretending every module is
  already a service.
- Engineers must maintain architecture checks as namespaces and dependencies
  become executable.
- Size limits can be exceeded only transparently; artificial fragmentation is
  not rewarded.

## Alternatives

- Microservices from the start: rejected because boundaries and operational
  load are not yet proven.
- Elixir umbrella applications for every context: rejected initially because
  they add compile/configuration boundaries without independent deployment.
- No automated size discipline: rejected because prior repositories accumulated
  oversized composition and prototype files.
- Absolute small-file limits: rejected because they incentivize indirection and
  damage cohesion.

## Validation

- `verify_foundation.ps1` validates durable authority.
- `verify_code_discipline.ps1` validates production source-file size and
  exception expiry.
- Gate 1 adds formatter, compiler-warning, Credo/static complexity, dependency,
  and architecture-boundary checks against real source code.

