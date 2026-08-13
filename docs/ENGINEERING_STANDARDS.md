# Engineering Standards

**Status:** Accepted greenfield baseline

These standards keep code understandable without turning line counts into an
architecture. Size thresholds are review signals. A justified exception is
preferable to artificial fragmentation, but exceptions must be explicit,
owned, dated, and temporary.

## 1. Source-size discipline

### Elixir

- Functions should normally remain below 25 logical lines.
- Functions above 40 logical lines require an explicit readability review.
- Functions above 80 logical lines require an approved exception or redesign.
- Production modules should normally remain below 350 physical lines.
- Modules above 500 lines require an explicit cohesion review.
- Production modules above 700 lines fail the size check unless allowlisted.
- Keep nesting to three decision levels where practical.
- Prefer a request/command/input struct over more than four positional
  parameters.

### TypeScript and React

- Functions should normally remain below 30 logical lines and require review
  above 50.
- React components should normally remain below 200 physical lines.
- TypeScript/TSX production files above 350 lines require cohesion review and
  fail above 550 lines unless allowlisted.
- Components coordinate presentation and user intent. Business policy and
  authorization never live only in the browser.

### Tests and generated artifacts

Tests may be longer when a scenario reads coherently, but should use fixtures
and helpers rather than repeat setup. Generated clients, migrations, fixtures,
vendored code, snapshots, and lockfiles are excluded from general source-size
limits and governed by their generators or specialized checks.

Physical file thresholds are enforced by
`scripts/verify_code_discipline.ps1`. Function complexity, nesting, warnings,
formatting, and static analysis become Mix/TypeScript checks in Gate 1.

## 2. File and module cohesion

- One file has one primary reason to change.
- One public module exposes one coherent capability.
- A business module may contain many files; a large bounded context is not a
  reason to create a network service.
- Split a module when vocabulary, invariants, permissions, lifecycle, data
  ownership, operational objectives, or change cadence are independently
  meaningful—not because a screen or table is large.
- Avoid `Utils`, `Helpers`, `Common`, and `Shared` dumping grounds. Name code
  after the business or technical capability it owns.

## 3. Elixir discipline

- Run `mix format --check-formatted` with no compiler warnings.
- Use pattern matching and tagged results for expected outcomes.
- Raise only for programmer errors or genuinely exceptional infrastructure
  failures; return typed domain/application errors for expected rejection.
- Do not use processes as a substitute for a data model. Persistent business
  truth belongs in PostgreSQL.
- Supervision trees isolate runtime failure; they do not grant retry safety.
  External effects still require idempotency and receipts.
- CPU-heavy or blocking native work must not block BEAM schedulers. Use bounded
  worker runtimes, ports, or carefully reviewed dirty-scheduler NIFs.
- Public functions require specs once the executable application exists.

## 4. Data and domain discipline

- Use opaque UUID identifiers at public boundaries.
- Store timestamps as UTC instants with explicit business timezone/calendar
  context where decisions depend on local time.
- Store money and physical quantities as decimal values with ISO currency or a
  governed unit-of-measure identifier. Never use binary floating point for
  monetary or contractual quantities.
- A state transition is a named command with preconditions, actor, tenant,
  reason, correlation, policy, evidence, idempotency, and audit behavior.
- Model rejection and HOLD states explicitly. Do not silently coerce missing
  evidence into success.
- Audit logging is not event sourcing. Current state remains directly
  queryable; events and evidence explain attributable changes.

## 5. API and event discipline

- Public APIs begin versioned under `/api/v1` and have generated OpenAPI
  contracts.
- Commands use stable intent-revealing names; unrestricted generic mutation
  endpoints are prohibited for consequential records.
- Integration events use a common envelope containing event id, version,
  tenant, aggregate identity, occurred time, actor/correlation/causation,
  classification, and payload.
- Events are recorded in the same database transaction as the state change and
  published through the outbox.
- Consumers are idempotent and retain processing receipts.
- Breaking API or event changes require a compatibility window and ADR.

## 6. Testing discipline

Every consequential command needs:

- success, validation, authorization, tenant-mismatch, state-conflict, and
  idempotent-replay tests;
- database constraint coverage for invariants that must survive application
  defects;
- audit/event/evidence assertions;
- external failure and retry behavior where applicable;
- an end-to-end scenario when it changes user-visible workflow.

Property and generative testing are preferred for money, quantity, scheduling,
state-machine, reconciliation, and policy invariants.

## 7. Dependency discipline

- Add a dependency only when it removes more risk or complexity than it adds.
- Record its owner, license, maintenance status, update policy, runtime impact,
  and exit path.
- Pin direct production dependencies to compatible bounded ranges and commit
  lockfiles.
- CI performs dependency, license, vulnerability, secret, and software bill of
  materials checks before release qualification.
- New languages, databases, queues, workflow products, or deployment platforms
  require an ADR and measured need.

## 8. External-identity discipline

- Product-facing source, APIs, events, catalogs, UI, fixtures, examples,
  diagrams, assessments, and documentation identify an external system by its
  business role, never by a company, product, account, or tenant-specific name.
- Stable role identifiers survive implementation changes. Provider bindings
  belong in deployment configuration behind typed anti-corruption adapters;
  they never become domain record types, module identifiers, permission names,
  event types, or user-interface labels.
- Exact implementation identity is permitted only when reproducible builds,
  dependency locks, security provenance, vulnerability response, licensing,
  interoperability, operator procedures, or an implementation-selection ADR
  would otherwise become unverifiable.
- Required exact identities must be minimal, attributable, and kept out of
  business payloads, logs, screenshots, examples, and public comparisons. This
  rule never removes license notices, security evidence, or software-bill-of-
  materials data.
- User-entered organization and counterparty names are governed business data,
  not implementation identities; preserve them under tenant, privacy,
  retention, and authorization policy.
- `config/external_identity_policy.json` and the foundation verifier enforce
  the approved role identifiers and an exact field schema for external-system
  entries in the module catalog.

## 9. Security-by-construction discipline

- Treat every external value, header, identifier, file, event, model output,
  and integration response as attacker-controlled until its boundary proves
  otherwise.
- Authenticate before resolving tenant-owned records, authorize the named
  command server-side, bind tenant scope in queries and constraints, and return
  uniform not-found/denied errors where disclosure matters.
- Prefer allowlists, structured parsers, parameterized queries, bounded reads,
  explicit timeouts, backpressure, and fail-closed configuration. Never build
  shell commands, SQL, paths, templates, URLs, or code from unchecked input.
- Require authenticated TLS for production HTTP, database, object-storage, and
  integration traffic. Forwarding headers are trusted only from an explicitly
  validated proxy peer; Host is never proof of local origin.
- Keep secrets out of source, logs, events, URLs, browser state, and error
  payloads. Reference managed secrets and test missing, empty, malformed, and
  rotated values.
- Verify every executable-producing artifact before use, including transitive
  bootstrap payloads. Bound network response bytes before digest verification.
  Extract archives member by member into new staging directories with path
  containment, duplicate-target, entry-type, count, and expanded-size
  enforcement. Revalidate persistent executable caches, including receipt,
  path type, owner, and write ACL, before use. Pin CI actions and container
  images, commit dependency locks, run advisory and secret checks, and review
  every dependency update for runtime authority and exit cost.
- Add a regression test for every validated vulnerability and demonstrate that
  the original malicious condition fails while legitimate behavior remains.
- A security review reports attacker, entry point, broken control, sensitive
  operation, prerequisites, impact, counterevidence, and remaining uncertainty.
  "Hacker-proof" is treated as a defense-in-depth goal, never a guarantee.

## 10. AI and agent discipline

- Keep model, prompt, retrieval, memory, and tool implementation concerns out of
  the product-neutral kernel. They enter through typed, bounded ports and
  replaceable role-based bindings.
- Treat prompts, retrieved documents, model output, agent memory, and tool
  responses as attacker-influenced data. Delimit, classify, validate, bound,
  attribute, and audit them before use or persistence.
- An agent has a distinct service identity and narrower delegated capability.
  It never inherits an actor's full session, creates permissions, approves its
  own work, or selects its own risk tier.
- Tools expose allowlisted typed operations, not generic database, filesystem,
  process, network, secret, or mutation access. Reauthorize every proposed
  business command against current tenant, permission, state, evidence, policy,
  idempotency, and human-task requirements.
- Persistent context requires declared ownership, tenant/actor/runbook/purpose
  isolation, provenance, classification, expiry, size limits, integrity,
  versioning, review, and revocation. Memory never overrides system policy.
- Runbooks declare schemas, allowed reads and proposed commands, evidence,
  approval, budgets, retries, recursion, timeouts, recovery, and release
  evaluation thresholds. Unlimited loops, tool chains, retries, tokens, time,
  or cost are prohibited.
- Record sufficient provenance to reproduce and assess material output without
  leaking sensitive prompts, credentials, private context, or protected raw
  content into general logs and events.
- Changes to runbooks, execution bindings, prompt templates, retrieval sources,
  tools, memory policy, or approval policy require task evaluations and
  adversarial regression checks proportionate to their risk.
- Consequential execution remains disabled until a bounded vertical has an ADR,
  deterministic command oracle, negative authorization and tenant tests,
  incident controls, monitored rollout, recovery, and rollback evidence.

## 11. Review and commit discipline

- One change solves one reviewable problem and advances the active gate.
- Avoid unrelated formatting, renaming, abstraction, or dependency churn.
- Commits state the outcome, not the editing activity.
- Pull requests report architecture impact, exact verification, operational
  risk, migration, rollout, and rollback.
- A temporary exception must not become an undocumented permanent architecture.
