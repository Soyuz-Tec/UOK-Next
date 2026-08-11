# ADR-0002: Selective Ash Adoption Requires a Spike

**Status:** Proposed

**Date:** 2026-08-11

## Context

Ash provides resources, named actions, policies, multitenancy, APIs, and
extensions that closely match the target business model. It also introduces a
substantial abstraction and learning boundary. The kernel must not become
opaque or force infrastructure concepts into resources.

## Proposed decision

Use Ash selectively for business resources and actions only if a Gate 1 spike
shows clearer policy, tenant, validation, transaction, API, testing, and change
behavior than explicit Phoenix/Ecto/application-service code.

Implement the same narrow party-onboarding slice both ways. Compare:

- business intent readability;
- fail-closed authorization and tenant behavior;
- transactional and concurrency semantics;
- generated API quality and frontend contracts;
- observability and error representation;
- migration and test ergonomics;
- compile time and developer workflow;
- escape hatches and framework coupling.

## Guardrails

- Module manifests, command receipts, evidence, integrations, and operational
  contracts remain explicit even if Ash is adopted.
- Durable external work uses the selected job/outbox boundary.
- A failed spike defaults to explicit Elixir/Phoenix/Ecto, not another
  framework search.

