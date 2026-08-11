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

## 8. Review and commit discipline

- One change solves one reviewable problem and advances the active gate.
- Avoid unrelated formatting, renaming, abstraction, or dependency churn.
- Commits state the outcome, not the editing activity.
- Pull requests report architecture impact, exact verification, operational
  risk, migration, rollout, and rollback.
- A temporary exception must not become an undocumented permanent architecture.

