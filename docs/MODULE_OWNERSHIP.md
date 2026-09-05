# Module and System Ownership

**Status:** Initial ownership authority

The machine-readable source is `config/module_catalog.json`. This document
explains its intent.

## Kernel and platform modules

| Module | Owns | Does not own |
|---|---|---|
| `platform.identity` | tenants, organizations, actors, password credentials, local access profiles, revocable regular and bootstrap sessions, service identities, authentication throttles; isolated local qualification authentication | parties and counterparties, production identity-provider policy |
| `platform.modules` | module definitions, reviewed installation records, compatibility, tenant enablement, surface registrations, verification receipts | business records or arbitrary runtime plugin execution |
| `platform.policy` | permissions, capability checks, policy decisions | domain approval facts |
| `platform.workflow` | workflow instances, human tasks, approval requests, escalations | source business records coordinated by a workflow |
| `platform.evidence` | evidence metadata, review state, audit events, integrity manifests | private communication content or source documents' business meaning |
| `platform.integrations` | connector configuration, health, external references, immutable party communication links, delivery-intent and reconciliation receipts | external systems' owned records |
| `platform.agents` | runbooks, generated plans, agent runs, agent approvals, tool receipts; future context or memory only after a catalog ownership update | business commands, permissions, policy facts, or records owned by target modules |

## Business modules

| Module | Initial authority |
|---|---|
| `master.parties` | parties, aliases, roles, relationships, sites, onboarding profiles |
| `master.products` | products, classifications, units, quality templates |
| `master.locations` | countries, versioned major-seaport references, tenant locations, corridors, route references |
| `operations.work` | native projects, work items, dependencies, calendars, comments |
| `trade.sourcing` | sourcing lanes, requisitions, RFQs, quote comparisons |
| `trade.contracts` | source-bound internal purchase-commitment proposals; future purchase/sale contracts, amendments, and external commercial commitments require separate authority |
| `trade.shipments` | source-bound non-executing shipment-readiness cases; future shipment plans, containers, milestones, execution, and logistics exceptions require separate authority |
| `trade.quality` | lots, samples, measurements, inspections, claims |
| `trade.compliance` | standards, requirements, clearance cases, compliance decisions |
| `trade.finance` | trade economics, landed cost, funding plans, FX exposure, risk controls |
| `intelligence.bi` | metric definitions, semantic models, reports, live operational-report projections, governed exports; never source business records or command authority |
| `public.publishing` | reviewed/redacted publication snapshots and public releases |

## External systems

| System | Authority | Integration rule |
|---|---|---|
| External communications system | communication content, delivery, calls, presence, membership | UOK stores typed business links and minimal projections; the owning system reauthorizes access |
| External collaborative-canvas system | canvas operations, convergence, snapshots | UOK supplies scoped authorization and business links; it does not implement a second merge engine |
| Document-intelligence workers | job-local extraction and inference results | results return as proposals/evidence and require UOK validation |
| Analytics execution plane | analytical execution over governed projections | no direct business mutation |
| Selected back-office system | only accounting, localization, HR, or inventory records selected by ADR | APIs/events only; no shared database |
| Evidence-anchor system | evidence-root submission and confirmation receipts | asynchronous and non-blocking; no PII or source documents leave the governed evidence boundary |

## Ownership change rule

Changing a system of record requires an ADR, migration and reconciliation plan,
dual-run or cutover evidence, rollback, retention decision, and updates to both
this document and `config/module_catalog.json`.

External-system names in product-facing material are role-based. Deployment
configuration may bind a role to an implementation, but that binding never
changes the role identifier or data-ownership contract. ADR-0010 and
`config/external_identity_policy.json` govern the exception for exact technical
identities.
