# Product Charter

**Status:** Accepted greenfield foundation

**Product:** UOK Next

## Mission

Build an evidence-first operating platform that helps organizations plan,
execute, understand, and govern multi-party commodity operations from source
and counterparty onboarding through procurement, shipment, quality,
compliance, sale, finance, reporting, and review.

## Product outcomes

UOK Next must enable a business to:

1. maintain governed parties, roles, relationships, products, classifications,
   locations, routes, and reference data;
2. configure reusable business-operation playbooks without duplicating the
   records owned by participating modules;
3. execute procurement, contract, shipment, quality, customs, finance, and
   exception workflows through explicit commands and human tasks;
4. make GO, HOLD, approval, release, and exception decisions from attributable
   evidence and policy;
5. connect communications and collaboration to the relevant business object
   without creating a second identity or authorization authority;
6. provide operational BI, economics, risk, lineage, and report-grade views;
7. allow AI to prepare, extract, reconcile, summarize, and recommend while
   preserving human and policy authority over consequential outcomes;
8. add countries, commodities, organizations, and integrations through
   configuration and modules rather than product forks.
9. preserve every previously developed application capability through native
   modules, governed specialist integrations or scoped local companions, with
   explicit source-to-target acceptance and recovery evidence. The durable
   requirement and initial inventory are in
   [Feature continuity](FEATURE_CONTINUITY.md) and ADR-0027.

## Primary users

- business owners and executives;
- trade, procurement, sales, logistics, quality, compliance, finance, and
  operations teams;
- field and partner users on constrained mobile networks;
- auditors, lenders, investors, and other authorized reviewers;
- administrators, integrators, and governed AI operators.

## First proving operation

The first end-to-end production-shaped slice is:

```text
Party onboarding
  -> product and sourcing lane
  -> RFQ and quote comparison
  -> purchase commitment proposal
  -> evidence and human approval
  -> shipment readiness and GO/HOLD gate
  -> operational and management report
```

Ghana raw cashew nuts and their linked packaging workflow provide realistic
test data, but the kernel and data model must remain commodity-neutral.

## Non-negotiable invariants

- One record type, one declared system of record.
- No consequential mutation without actor, tenant, command, reason,
  correlation, policy decision, and audit evidence.
- No module writes another module's private data.
- No AI, blockchain, communications provider, UI, or integration becomes a
  second command bus or permission system.
- Prompt text, retrieved context, model output, agent memory, and tool responses
  are untrusted inputs. None can grant authority, satisfy approval, or become a
  policy fact without deterministic validation and attributable acceptance.
- An AI-proposed mutation uses a typed business command with fresh tenant,
  permission, subject-version, idempotency, evidence, policy, and human-review
  checks. Plan approval is never reusable execution authority.
- Missing required evidence produces HOLD, not an optimistic assumption.
- External side effects are idempotent, receipt-backed, observable, and
  recoverable.
- Private communications are not evidence unless intentionally promoted
  through an authorized evidence workflow.
- Production claims require tests, runtime evidence, recovery evidence, and an
  identified rollback.

## Current non-goals

- Running a custom blockchain or optimistic rollup.
- Autonomous settlement, payment, customs filing, legal acceptance, or
  regulated approval.
- Reimplementing general ledger, payroll, or every national localization before
  evaluating a maintained specialist system.
- Starting with microservices, Kafka, Kubernetes, or a data lake before proven
  load and isolation requirements exist.
- Porting prototype files line by line merely to retain sunk cost.
