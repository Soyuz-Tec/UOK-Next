# ADR-0013: Governed non-executing agent plans

**Status:** Accepted

**Date:** 2026-08-12

## Context

Gate 2 requires a governed agent-plan primitive, but the repository does not
yet have production identity, server-owned runbook definitions, model/tool
execution, scheduling, budgets, or business-command APIs. Treating a generated
plan or its human approval as execution authority would bypass deterministic
business policy and create an unsafe confused-deputy boundary before those
controls exist.

The kernel needs a durable proposal and review envelope that can later support
measured agent capabilities without prematurely selecting a model runtime or
allowing advisory output to mutate records.

## Decision

- `platform.agents` owns agent plans. A plan records its tenant, stable runbook
  key and version reference, governed subject identity/version, bounded evidence
  references, deterministic step graph, SHA-256 digest, lifecycle, review-task
  reference, actors, reasons, timestamps, and optimistic lock version.
- A proposal contains 1 to 32 uniquely identified steps. Step action is limited
  to `read`, `prepare`, `reconcile`, `recommend`, or `propose_command`; titles
  and dependency lists are bounded, all dependencies must resolve inside the
  plan, and the graph must be acyclic.
- Proposal input rejects model, prompt, tool, endpoint, argument, and command
  execution fields. The stored plan contains no credentials, executable
  payload, external endpoint, or raw model/tool output.
- The server canonicalizes validated plan identity, graph, and evidence
  references and derives the plan digest. Exact duplicate plan content is
  rejected independently of command idempotency.
- Proposing a plan atomically creates one `platform.workflow` human task bound
  to the plan identifier and version. Plan, task, command receipt, two audit
  events, and two outbox events commit or roll back together.
- Approval or hold must consume the exact recorded task, tenant, plan, and
  version under `agents:plan:approve`. It changes only the plan and task review
  lifecycle. Every public response, audit record, and plan event records
  `execution_authorized: false`.
- Proposal, decision, and read use separate named permissions. Application
  queries include tenant predicates; PostgreSQL forces row-level security and
  lifecycle/graph/digest bounds.
- Plan approval never dispatches a connector, model, tool, scheduler, workflow,
  or business command. A future command would require its own named permission,
  fresh server-side subject/version policy, idempotency, audit, evidence, and
  any required human task; this ADR supplies no authority for it.

## Consequences

The kernel can preserve, review, replay, and audit a deterministic advisory plan
without creating an autonomous execution path. Cross-tenant, cross-task, stale,
duplicate, cyclic, executable-field, and consumed-task attempts fail closed.
The runbook reference is an identity only; server-owned runbook definitions and
their policy semantics remain explicitly unimplemented.

## Alternatives

- Execute an approved plan directly: rejected because plan review is not
  command-specific authorization and cannot replace current record policy.
- Store free-form model prompts, tool arguments, or endpoints: rejected because
  they create unbounded secret, injection, SSRF, and code-execution surfaces.
- Keep plans in process memory: rejected because review, replay, recovery,
  tenant isolation, and audit evidence would be lost.
- Adopt a general agent framework now: rejected because no measured business
  vertical justifies its runtime, tool, scheduling, or failure semantics.

## Validation

- Integration tests prove atomic plan/task proposal and decision, stable replay,
  replay conflict, duplicate rollback, exact task consumption, audit/outbox
  evidence, and zero connector receipts after approval.
- Negative tests cover missing named permissions, stale state, cross-task and
  cross-tenant substitution, consumed-task reuse, duplicate/unknown/cyclic
  dependencies, disallowed actions, execution fields, and graph-size bounds.
- Forced row-level security, tenant-scoped locked reads, optimistic locking,
  database lifecycle/graph/digest constraints, architecture checks,
  code-discipline checks, and security review remain mandatory before
  publication.
