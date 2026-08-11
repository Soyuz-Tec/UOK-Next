# Module and System Ownership

**Status:** Initial ownership authority

The machine-readable source is `config/module_catalog.json`. This document
explains its intent.

## Kernel and platform modules

| Module | Owns | Does not own |
|---|---|---|
| `platform.identity` | tenants, organizations, actors, sessions, service identities | parties and counterparties |
| `platform.modules` | module catalog, lifecycle, tenant enablement | business records |
| `platform.policy` | permissions, capability checks, policy decisions | domain approval facts |
| `platform.workflow` | workflow instances, human tasks, approval requests, escalations | source business records coordinated by a workflow |
| `platform.evidence` | evidence metadata, review state, audit events, integrity manifests | private communication content or source documents' business meaning |
| `platform.integrations` | connector configuration, health, external references, receipts | external systems' owned records |
| `platform.agents` | runbooks, generated plans, agent runs, agent approvals, tool receipts | business commands or records owned by target modules |

## Business modules

| Module | Initial authority |
|---|---|
| `master.parties` | parties, aliases, roles, relationships, sites, onboarding profiles |
| `master.products` | products, classifications, units, quality templates |
| `master.locations` | countries, locations, corridors, route references |
| `operations.work` | native projects, work items, dependencies, calendars, comments |
| `trade.sourcing` | sourcing lanes, requisitions, RFQs, quote comparisons |
| `trade.contracts` | purchase/sale contracts, amendments, commercial commitments |
| `trade.shipments` | shipment plans, containers, milestones, logistics exceptions |
| `trade.quality` | lots, samples, measurements, inspections, claims |
| `trade.compliance` | standards, requirements, clearance cases, compliance decisions |
| `trade.finance` | trade economics, landed cost, funding plans, FX exposure, risk controls |
| `intelligence.bi` | metric definitions, semantic models, reports, governed exports |
| `public.publishing` | reviewed/redacted publication snapshots and public releases |

## External systems

| System | Authority | Integration rule |
|---|---|---|
| K-Comms | communication content, delivery, calls, presence, membership | UOK stores typed business links and minimal projections; K-Comms reauthorizes access |
| K-Board | canvas operations, convergence, snapshots | UOK supplies scoped authorization and business links; it does not implement a second merge engine |
| Python workers | job-local extraction and inference results | results return as proposals/evidence and require UOK validation |
| Rust analytics | analytical execution over governed projections | no direct business mutation |
| Odoo | only selected accounting, localization, HR, or inventory records declared by ADR | APIs/events only; no shared database |
| Blockchain anchor | evidence-root submission and confirmation receipts | asynchronous and non-blocking; no PII or documents on-chain |

## Ownership change rule

Changing a system of record requires an ADR, migration and reconciliation plan,
dual-run or cutover evidence, rollback, retention decision, and updates to both
this document and `config/module_catalog.json`.

