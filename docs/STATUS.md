# Current Build Status

**Snapshot date:** 2026-08-11

**Repository:** `C:\Users\vasan\OneDrive\Documents\uok 2`

**Canonical repository:** `https://github.com/Soyuz-Tec/UOK-Next`

**Visibility/default branch:** public, protected `main`

## One active focus

**Gate 1: prove the Phoenix runtime skeleton and compare selective Ash against
explicit Elixir/Ecto for one tenant-scoped party-onboarding slice.**

## Verified in this increment

- The workspace is an empty Git repository suitable for a greenfield start.
- Node.js, npm, Rust, Cargo, Python, and Podman are available on the Windows
  development host.
- The pinned Erlang/OTP 28.4 and Elixir/Mix 1.20.2 toolchain is installed in
  the current user's versioned `.elixir-install` directory and added to the
  user `PATH`.
- Initial product, architecture, ownership, roadmap, continuity, and decision
  documents have been created.
- A machine-readable module catalog and PowerShell verification command have
  been added.
- The modular-monolith source layout, dependency direction, transaction rules,
  tenancy baseline, module split/extraction tests, and code-size discipline are
  accepted and machine-checked.
- Elixir 1.20.2, Erlang/OTP 28.4, and the Phoenix 1.8.9 generator are pinned in
  `config/toolchain.json`; the checked-in setup downloads the exact OTP and
  Elixir ZIP assets, verifies repository-owned SHA-256 identities, safely
  extracts them, and installs them into content-addressed directories.
- Hex 2.5.1, Rebar3 3.25.1, and the pinned Phoenix 1.8.9 generator are installed
  and verified through the checked-in framework-tool setup script.
- The public GitHub repository exists, `main` is protected, foundation CI is
  required, administrators are included, direct force-push/deletion is denied,
  conversations must resolve, and squash/linear history is enforced.
- The API-only Phoenix 1.8.9 skeleton and versioned `/api/v1/health` endpoint
  are scaffolded on `codex/gate-1-framework-spike` for verification.
- PostgreSQL 18.4 is pinned by multi-platform image digest, runs locally on
  loopback port 15432, and passed the Ecto setup/test path.
- Phoenix, Ash candidate, PostgreSQL adapter, Credo, and Sobelow dependencies
  are locked; `mix quality`, `mix hex.audit`, foundation verification, and code
  discipline verification pass locally.
- A live Bandit smoke test returned the expected release identity from
  `GET /api/v1/health` on `127.0.0.1`.
- The first complete repository security scan recorded three low-severity
  foundation findings: mutable installer execution, untrusted proxy/Host
  transport metadata, and plaintext-default production PostgreSQL transport.
- The bounded security-hardening increment pins and verifies the installer,
  fails closed on production origin/database transport, removes unused
  production parser/session/socket surface, and adds regression/CI controls.
- Diff-scoped adversarial review reproduced an Ecto URL-precedence bypass of
  the first database TLS control. The corrected baseline rejects URL-owned SSL
  options and verifies Ecto's effective normalized configuration.
- A second diff audit found one low-severity bootstrap trust gap: Hex metadata
  and its artifact shared a publication channel. Hex and Rebar3 now use exact
  repository-owned URLs and SHA-512 pins, and every downloaded byte is checked
  before installation; existing local Rebar3 files are no longer trusted.
- The completed remediation scan closed all 12 review rows with no reportable
  findings. Hex's signed package checksums already protected the Phoenix
  generator, and the baseline now adds a repository-owned Phoenix package
  SHA-512 before extraction and local archive build as an independent control.
- A subsequent publication-gate scan closed all 12 review rows and found one
  low-severity transitive bootstrap gap: the authenticated installer still
  fetched unchecked OTP and Elixir ZIPs. The installer path has been removed;
  both archives are now independently pinned and safely extracted, while ZIP
  and TAR traversal, link-like entries, entry counts, and expanded sizes fail
  closed before executable use.
- The final candidate scan closed all 12 review rows and all four candidate
  ledgers with no reportable finding. Defense-in-depth follow-through adds
  exact response-size pins, curl streaming ceilings and partial-file cleanup,
  full-digest install paths, protected-parent staging, install receipts,
  reparse/owner/write-ACL checks, normalized duplicate-target rejection, and
  an explicit digest for Phoenix's inner source archive.

## Gate 1 remaining work

1. Implement equivalent explicit Elixir/Ecto and Ash party-onboarding paths.
2. Run the evaluation matrix and record ADR-0002's final decision.
3. Retain the selected implementation and remove the losing candidate.

## Explicitly not yet implemented

- Party onboarding, Ash selection, React, persistent business modules, object
  storage, durable jobs, integrations, or blockchain anchoring.
- No production-readiness claim exists.

## Next action

Implement the explicit Elixir/Ecto party-onboarding path and its shared
contract tests before implementing the equivalent Ash candidate.
