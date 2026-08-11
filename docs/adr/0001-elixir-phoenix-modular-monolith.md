# ADR-0001: Elixir/Phoenix Modular Monolith Foundation

**Status:** Accepted

**Date:** 2026-08-11

## Context

The prior GitHub estate proves valuable business concepts across UOK, Kayilan
Atlas, Kayilan CTRM, K-Comms, and K-Board, but it duplicates foundational
concerns across Python, JavaScript/TypeScript, and Elixir implementations. The
new platform needs strong concurrency, fault containment, durable business
actions, human workflows, real-time coordination, audit, and a small deliberate
language set.

## Decision

Build the product-neutral kernel and in-process business modules as an
Elixir/Phoenix application on Erlang/OTP and PostgreSQL. Start as a modular
monolith with one release and explicit module boundaries. Retain React and
TypeScript for the primary application surfaces.

## Consequences

- K-Comms operational experience and BEAM expertise become directly reusable.
- Real-time and background work share OTP supervision and observability
  primitives.
- CPU-heavy analytics, CRDTs, OCR, and model execution require bounded Rust or
  Python runtimes.
- Elixir/Erlang hiring and training need an explicit plan.
- Service extraction requires a later evidence-backed ADR.

## Alternatives

- Direct Erlang: retains OTP but gives up material Phoenix/Elixir productivity.
- Rust for the entire kernel: excellent performance but slower development for
  policy-heavy ERP workflows and a weaker application ecosystem fit.
- Python/FastAPI or TypeScript: productive but duplicates the strongest proven
  runtime in the estate and provides weaker native fault/concurrency semantics.
- C++: unjustified safety and development cost for this domain.
- Odoo as kernel: strong standard ERP breadth but constrains the differentiated
  evidence/workflow/agent architecture.

## Validation

Gate 1 must prove reproducible builds, policies, tenant isolation, audit,
commands, durable work, API generation, UI integration, container health, and
representative load before the stack is considered runtime-proven.

