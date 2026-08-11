# Gate 1 Framework Spike

**Status:** In progress

## Question

Should business modules use selective Ash resources/actions/policies, or should
they use explicit Elixir application services and Ecto schemas throughout?

The Phoenix/OTP delivery and runtime decision is already accepted. This spike
decides only the internal business-module implementation approach.

## Scope

Implement the same narrow tenant-scoped party-onboarding behavior twice under
`spikes/`:

- explicit Elixir/Ecto path;
- Ash/AshPostgres/AshPhoenix path.

The comparison must cover:

1. create a draft organization party;
2. validate stable identity, country, name, party kind, and tenant;
3. deny tenant mismatch and missing actor authority;
4. submit onboarding evidence metadata;
5. approve or place the profile on HOLD through a named action;
6. prevent stale/concurrent state transition;
7. emit attributable audit and outbox records transactionally;
8. expose equivalent API/error contracts;
9. exercise migrations, unit, policy, database, and HTTP tests.

## Evaluation matrix

Each path is scored with concrete code/test evidence for:

- business intent readability;
- policy and tenant correctness;
- transaction and concurrency clarity;
- error and API contract quality;
- audit/outbox integration;
- migration and test ergonomics;
- framework coupling and escape hatches;
- compile/test feedback and source complexity.

## Stop rules

- Do not add unrelated modules or UI breadth.
- Candidate dependencies remain dev/test-only until ADR-0002 is accepted or
  rejected from evidence.
- Do not create empty target-architecture folders.
- The losing implementation is removed after useful fixtures and contract
  tests are preserved.

## Exit

Update ADR-0002 with measured results, select one implementation model, remove
the losing production candidate, and make the selected path pass the full Gate
1 quality suite.

