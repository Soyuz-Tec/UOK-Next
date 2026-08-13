# ADR-0017: Deterministic AI authority boundary

**Status:** Accepted

**Date:** 2026-08-12

## Context

The product charter allows AI to prepare, extract, reconcile, summarize, and
recommend while preserving deterministic policy and human authority over
consequential outcomes. ADR-0013 implemented only durable, non-executing agent
plans. It deliberately did not define model execution, tools, memory,
scheduling, budgets, or business-command authority.

Current AI risk and agent-security research reinforces that an AI-compatible
business kernel must treat prompts, retrieved context, model output, persistent
memory, and tool responses as attacker-influenced data. Tool overreach, memory
poisoning, prompt injection, goal manipulation, data disclosure, uncontrolled
loops, and approval manipulation cannot be solved by model instructions alone.

The architecture therefore needs a durable target before any executable agent
surface is designed. Compatibility with AI does not mean embedding probabilistic
decision authority in the kernel.

## Decision

- The kernel remains deterministic and product-neutral. It contains no model,
  prompt, retrieval, memory, provider, or agent-framework policy. It governs AI
  through the same tenant, actor, permission, command, idempotency, evidence,
  audit, outbox, and recovery primitives used by human-initiated work.
- AI output is untrusted and advisory. It cannot grant permissions, satisfy an
  approval, select its own risk tier, alter policy, or write a business record.
- Model and document-intelligence execution runs outside the kernel behind
  typed, bounded ports. A replaceable implementation binding cannot change
  domain commands, permissions, evidence requirements, or record ownership.
- `platform.agents` will own versioned server-side runbooks. A runbook declares
  its purpose, risk tier, accepted input and output schemas, data
  classification, allowed read capabilities, allowed proposed commands,
  evidence requirements, approval policy, time and cost budgets, retry and
  recursion ceilings, and recovery behavior.
- Every agent run uses a distinct service identity and an attributable human or
  system sponsor. Effective authority is the intersection of sponsor
  delegation, agent capability, tenant policy, module command policy, and
  current subject state. The command boundary reauthorizes every proposed
  mutation; a plan or earlier approval is never a bearer permission.
- Tools expose narrow typed operations. Agents receive no unrestricted database,
  filesystem, process, network, secret, or generic mutation access. Tool input
  and output are schema-validated, size-bounded, classified, and recorded with a
  receipt. Untrusted tool output cannot become an instruction or policy fact.
- Persistent context requires an explicitly declared record owner before
  implementation. It is tenant-, actor-, runbook-, and purpose-scoped;
  provenance-labelled; classified; size- and time-bounded; integrity-checked;
  versioned; reviewable; and revocable. Memory is never a trusted extension of
  system policy.
- A consequential proposed command requires fresh server-side permission,
  tenant and subject-version validation, deterministic policy, idempotency, and
  the exact human task required by its business module. Only an explicitly
  classified low-risk command may omit human review, and that exception requires
  its own ADR, negative tests, limits, and emergency revocation path.
- Each material result records runbook and policy versions, execution-role and
  binding revisions, input and evidence digests, output schema and digest, tool
  receipts, budget consumption, decision evidence, and final command receipts.
  Sensitive prompts, credentials, private context, and raw protected content do
  not enter general logs or business events.
- Production activation requires task evaluations, known-truth comparisons,
  prompt-injection and tool-abuse tests, memory-poisoning tests, cross-tenant and
  data-disclosure tests, budget-exhaustion tests, rollback drills, and monitored
  release thresholds. A change to runbook, model binding, prompt template,
  retrieval source, tool, memory policy, or approval policy triggers
  requalification.
- No executable agent vertical opens while the active RFQ and quote-comparison
  slice lacks deterministic commands and end-to-end qualification. ADR-0013
  remains the only implemented agent capability until a later ADR proves one
  bounded execution outcome.

## Consequences

AI can evolve independently without becoming a second command bus, permission
system, workflow engine, or system of record. Business correctness remains
testable without a model, and model failure degrades to unavailable advice
rather than unauthorized mutation.

The design requires more explicit schemas, receipts, evaluation data, operator
controls, and recovery work than a direct model-to-tool integration. That cost
is accepted because the application handles multi-party commercial decisions
where silent authority expansion is unacceptable.

## Alternatives

- Put model calls and prompt policy in the kernel: rejected because
  probabilistic implementation concerns would contaminate product-neutral
  authority and release safety.
- Let an approved plan execute all of its steps: rejected because plan approval
  cannot replace command-specific reauthorization against current state.
- Give an agent the sponsoring user's full session authority: rejected because
  delegation must be narrower, attributable, expiring, and independently
  revocable.
- Trust persistent memory or retrieved documents as instructions: rejected
  because both are attacker-influenced data and can preserve malicious context.
- Adopt autonomous execution before deterministic business commands exist:
  rejected because no reliable policy, rollback, or evaluation oracle would
  exist.

## Validation

- architecture checks continue proving that the kernel imports no business or
  AI execution module;
- agent plans continue returning `execution_authorized: false` and creating no
  connector or business-command receipt;
- future executable-agent work supplies the negative, evaluation, budget,
  provenance, incident, recovery, and exact-command evidence required above;
  and
- `docs/STATUS.md` distinguishes this accepted target from implemented runtime
  capability.
