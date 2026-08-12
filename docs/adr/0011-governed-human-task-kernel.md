# ADR-0011: Governed human-task kernel

**Status:** Accepted

**Date:** 2026-08-12

## Context

Gate 2 requires a durable human-decision boundary before autonomous work,
external connectors, or broader business workflows can safely mutate records.
A status field on a business record is insufficient: it does not identify the
exact subject version under review, prove who was authorized to decide, prevent
cross-tenant or cross-subject substitution, or provide an independent task
lifecycle for recovery and operations.

The first proving use case is party onboarding. Submitted evidence must create
one review obligation, and an approval or hold decision must consume that exact
obligation without splitting business state, task state, audit evidence, and
outbox records across transactions.

## Decision

- `platform.workflow` owns governed human tasks. A task records its tenant,
  stable task kind, subject type and identifier, exact subject version, required
  permission, opening actor and reason, lifecycle state, resolution, completing
  actor, timestamps, and optimistic lock version.
- Opening and completing a task occur inside the coordinating business
  command's existing `CommandTransaction`. The business mutation, task
  mutation, command receipt, append-only audit events, and outbox events either
  commit together or roll back together.
- A completion is valid only when the task is open and the supplied subject
  type, subject identifier, and subject version exactly match the governed task.
  The current actor must hold the task's recorded permission.
- Task lookup is tenant-scoped in both application queries and forced database
  row-level security. A missing, foreign-tenant, or substituted task is not
  usable as authority for a business decision.
- The first lifecycle is intentionally narrow: evidence submission opens one
  onboarding-review task; `approve` and `hold` are the only exposed
  resolutions. General workflow definitions, delegation, assignment,
  escalation, cancellation, deadlines, and notification delivery remain
  unimplemented until a business vertical proves their semantics.
- The workflow public boundary is an internal typed module contract, not a
  user-facing generic task mutation API. The coordinating business module owns
  its decision rules and supplies audit and outbox representations for both
  records.

## Consequences

Human authorization becomes a first-class, replay-safe kernel invariant rather
than a UI convention. Concurrent or stale completion fails closed, and a party
cannot be approved with a task for another tenant, subject, or version. The
initial design deliberately avoids a generic workflow engine and does not yet
provide task inbox queries, assignment, escalation, or durable notification.

Supporting multiple audit records per command is now part of the transaction
contract so a coordinated business change can preserve evidence for each
owned record without creating a second transaction.

## Alternatives

- Keep only the party status and audit event: rejected because it cannot prove
  or recover the independent review obligation.
- Accept any open task of the same type: rejected because subject substitution
  would turn task possession into unintended authority.
- Complete the task after the business transaction: rejected because failures
  would leave contradictory task and business state.
- Adopt a general workflow engine now: rejected because no measured Gate 2
  requirement justifies its state model or operational cost.

## Validation

- Contract and integration tests prove atomic task creation and completion with
  command receipts, two audit events, and two outbox events.
- Negative tests cover missing permission, foreign tenant, wrong subject,
  stale subject state, already-consumed tasks, and idempotent replay/conflict.
- Forced row-level security, tenant-scoped locked reads, database constraints,
  optimistic locking, architecture checks, and code-discipline checks remain
  mandatory.
- The changed production and migration surface completed a repository-scoped
  security diff review before publication.
