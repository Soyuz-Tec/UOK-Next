# Decision Log

Material decisions live in ADRs. This file is a short index and review queue.

| ADR | Decision | Status | Review trigger |
|---|---|---|---|
| [0001](adr/0001-elixir-phoenix-modular-monolith.md) | Elixir/Phoenix modular monolith is the greenfield foundation | Accepted | Measured inability to meet a required quality attribute |
| [0002](adr/0002-selective-ash-adoption-spike.md) | Explicit Elixir/Ecto is selected; Ash is not adopted in the production graph | Accepted | Measured module-specific need that justifies a new bounded spike |
| [0003](adr/0003-specialist-runtime-authority.md) | K-Comms, K-Board, Python, Rust, and Odoo retain bounded authority | Accepted | A proposed ownership or runtime-boundary change |
| [0004](adr/0004-blockchain-is-an-optional-evidence-anchor.md) | Blockchain is optional anchoring infrastructure, not the kernel | Accepted | Approved legal/business case beyond evidence anchoring |
| [0005](adr/0005-modular-monolith-and-code-discipline.md) | One Phoenix/Mix modular monolith with explicit boundaries and review-based source-size discipline | Accepted | Proven boundary failure or extraction requirement |
| [0006](adr/0006-operational-kernel-and-local-ha-qualification.md) | Durable command transactions and a bounded two-replica local HA qualifier | Accepted | Production platform selection or measured recovery failure |
| [0007](adr/0007-postgresql-19-data-platform-foundation.md) | PostgreSQL 19 is the governed data-platform target; Beta 2 is qualification-only | Accepted with production GA gate | PG19 GA, production platform selection, or measured database objective failure |
