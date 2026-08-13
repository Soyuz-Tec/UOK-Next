# Decision Log

Material decisions live in ADRs. This file is a short index and review queue.

| ADR | Decision | Status | Review trigger |
|---|---|---|---|
| [0001](adr/0001-elixir-phoenix-modular-monolith.md) | Elixir/Phoenix modular monolith is the greenfield foundation | Accepted | Measured inability to meet a required quality attribute |
| [0002](adr/0002-selective-ash-adoption-spike.md) | Explicit Elixir/Ecto is selected; Ash is not adopted in the production graph | Accepted | Measured module-specific need that justifies a new bounded spike |
| [0003](adr/0003-specialist-runtime-authority.md) | Specialist runtimes and external systems retain bounded role-based authority | Accepted | A proposed ownership or runtime-boundary change |
| [0004](adr/0004-blockchain-is-an-optional-evidence-anchor.md) | Blockchain is optional anchoring infrastructure, not the kernel | Accepted | Approved legal/business case beyond evidence anchoring |
| [0005](adr/0005-modular-monolith-and-code-discipline.md) | One Phoenix/Mix modular monolith with explicit boundaries and review-based source-size discipline | Accepted | Proven boundary failure or extraction requirement |
| [0006](adr/0006-operational-kernel-and-local-ha-qualification.md) | Durable command transactions and a bounded two-replica local HA/browser qualifier | Accepted | Production platform selection or measured recovery failure |
| [0007](adr/0007-postgresql-19-data-platform-foundation.md) | PostgreSQL 19 is the governed data-platform target; Beta 2 is qualification-only | Accepted with production GA gate | PG19 GA, production platform selection, or measured database objective failure |
| [0008](adr/0008-react-typescript-delivery-foundation.md) | One React/TypeScript workspace compiles into the Phoenix release; browser policy remains server-owned | Accepted | A proven SSR, offline, scaling, or separate-delivery requirement |
| [0009](adr/0009-provider-neutral-s3-evidence-object-foundation.md) | A provider-neutral S3 port governs evidence bytes; SeaweedFS 4.37 is local/CI qualification only | Accepted with production-provider gate | Production platform selection or a measured S3 compatibility/durability failure |
| [0010](adr/0010-role-based-external-system-identification.md) | Product-facing external systems use role-based identities; exact implementation identities are restricted to technical evidence | Accepted | A new external role, identity disclosure, or implementation-binding change |
| [0011](adr/0011-governed-human-task-kernel.md) | Human decisions consume an exact tenant- and subject-version-bound task in the coordinating command transaction | Accepted | A new task lifecycle, assignment, delegation, escalation, or external workflow boundary |
| [0012](adr/0012-provider-neutral-connector-receipts.md) | Connector side effects use immutable attempt receipts and bounded reconciled outcomes | Accepted | Live transport, credential, scheduling, dead-letter, or connector-definition work |
| [0013](adr/0013-governed-non-executing-agent-plans.md) | Agent plans are bounded advisory DAGs whose human approval never authorizes execution | Accepted | Runbook definitions, model/tool execution, scheduling, budgets, or command authorization |
| [0014](adr/0014-gate-3-party-onboarding-vertical.md) | Gate 3 begins with tenant-authenticated, evidence-bound party onboarding and exact human review | Accepted | Production identity selection or a changed party-onboarding authority |
| [0015](adr/0015-product-location-and-sourcing-lane-authority.md) | Product, location, and sourcing-lane ownership remains explicit across public module contracts | Accepted | Product/location ownership changes or a new sourcing-lane lifecycle |
| [0016](adr/0016-security-scan-artifact-sealing-waiver.md) | A bounded artifact-sealing waiver preserves verifiable security-scan evidence | Accepted | Scanner replacement or a reproducible sealed-artifact path |
| [0017](adr/0017-deterministic-ai-authority-boundary.md) | Probabilistic work remains advisory behind deterministic policy, evidence, and current command authorization | Accepted | Any model, tool, memory, scheduler, or agent command execution |
| [0018](adr/0018-module-neutral-composition-and-installation.md) | Module installation and tenant enablement belong to a neutral platform composition boundary | Accepted | Dynamic installation, compatibility, migration receipts, or disabled-module qualification |
| [0019](adr/0019-attributable-rfq-and-deterministic-quote-comparison.md) | RFQs and evidence-bound quotes produce a deterministic, human-approved comparison without purchase commitment | Accepted | Formula change, negotiation, partial/split award, normalization, or commitment creation |
| [0020](adr/0020-source-bound-purchase-commitment-proposal.md) | One approved comparison can create one source-derived, non-binding proposal with fresh reauthorization and exact review | Accepted | Contract/order formation, edited terms, downstream dispatch, payment, or inventory action |
