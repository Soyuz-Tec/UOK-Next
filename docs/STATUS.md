# Current Build Status

**Snapshot date:** 2026-08-26

**Canonical repository:** `https://github.com/Soyuz-Tec/UOK-Next`

**Visibility/default branch:** public, protected `main`

## One active focus

**Gate 3: deliver the first end-to-end business operation.**

## Verified foundation

- The accepted foundation is an Elixir 1.20.2, Erlang/OTP 28.4, Phoenix 1.8
  modular monolith targeting PostgreSQL 19. PG19 Beta 2 is digest-pinned for
  local/CI compatibility; production remains gated on PG19 GA/current minor.
- Toolchain archives, framework bootstrap artifacts, GitHub Actions, base
  images, PostgreSQL, and HAProxy are pinned to repository-owned hashes or
  immutable digests and fail closed on identity mismatch.
- Architecture, module ownership, code discipline, production transport
  controls, and release decisions are repository-owned and machine-checked.
- External systems now use stable role-based identities in product-facing
  architecture, catalogs, contracts, UI, and documentation. Exact
  implementation identities are restricted to reproducibility, security,
  licensing, interoperability, operations, and selection-decision evidence;
  the module catalog rejects every field outside its governed role schema.
- `main` is protected; Foundation CI, review resolution, linear history, and
  administrative enforcement remain delivery gates.

## Gate 1 exit evidence

- Equivalent explicit Ecto and Ash party-onboarding candidates were built
  against one contract and measured. ADR-0002 selects explicit Elixir/Ecto;
  the Ash candidate and all Ash dependencies were removed.
- `master.parties` now has a narrow governed onboarding slice: draft creation,
  evidence submission, approval/hold decisions, tenant-safe reads, named
  permissions, mandatory reasons, optimistic concurrency, and stable identity.
- Mutations atomically persist business state, an idempotent command receipt,
  append-only audit evidence, and versioned outbox events.
- PostgreSQL forces row-level tenant isolation. Runtime replicas use a dedicated
  non-superuser, non-`BYPASSRLS` role and activate a validated tenant only for
  the current database transaction; migrations use a separate owner role.
- Liveness, admission-limited cached readiness/startup, immutable release
  identity, bounded database timeouts, authenticated Prometheus metrics, and
  command telemetry are implemented.
- The release builds in a non-root, read-only container with dropped
  capabilities and bounded CPU, memory, process, and temporary-file resources.
- The supported local qualifier runs one migration job and two identical app
  replicas behind HAProxy. Readiness, release identity, metrics authorization,
  reconciled least-privileged database access, DNS refresh, per-replica image
  identity, single-replica failover, and an HTTP 200 browser-shell request have
  been exercised on Podman. Plaintext shell delivery fails closed unless the
  explicit local profile, loopback host, private container binding, isolated
  database, and isolated object store all match; production HTTPS is unchanged.
- Application tests include authorization, input, tenant mismatch, database
  row-level isolation, atomic audit/outbox/receipt creation, replay conflict,
  stale state, unavailable dependencies, schema-readiness failure paths, and a
  pre-migration PG19 major/prerelease compatibility gate.
- ADR-0007 now governs PostgreSQL as a complete data platform: deterministic
  UTF-8 cluster identity, checksums, SCRAM, explicit roles/default privileges,
  connection budgets, CA-authenticated TLS, tenant-aware foreign keys,
  migration safety, HA/fencing, WAL/PITR, restore drills, observability,
  vacuum/freeze, capacity, retention, and upgrades. Machine checks exercise
  the initial PG19 cluster and policy invariants.
- ADR-0008 now governs the UI delivery boundary. A responsive, accessible,
  module-neutral React 19.2 shell is implemented with one read-only readiness
  contract and no browser-owned business policy.
- Node 24 LTS, npm 11, Vite 8, native TypeScript 7, and the bounded TypeScript 6
  tooling API are exactly pinned. Format, lint, dual type checks, unit tests,
  advisory audit, architecture policy, and production build now run in CI.
- Content-hashed UI assets are built in a digest-pinned Node stage and copied
  into the same non-root Phoenix release. Phoenix applies a restrictive CSP,
  framing denial, no-store, referrer, MIME-sniffing, and browser-capability
  headers to the shell response.
- Local rendered proof covers 1440-by-1000 desktop and 390-by-844 phone
  viewports through the Phoenix delivery path: readiness reached `Kernel ready`,
  no horizontal overflow or console errors remained, and no business mutation
  control was exposed.
- The UI increment passed all protected foundation, application, and release
  checks in PR #7 and was squash-merged. The exact merged revision was rebuilt
  into both local application replicas; readiness/release identity and
  single-replica failover passed without bypassing a delivery gate.
- ADR-0009 establishes a provider-neutral S3 evidence-byte boundary. The
  digest-pinned SeaweedFS 4.37 local/CI qualifier runs non-root with bounded
  resources, fresh credentials, loopback-only exposure, and unused external
  surfaces disabled or unexposed; it is not a production-provider selection.
- Evidence candidates are limited to 8 MiB, start quarantined, use allowlisted
  media types and server-derived tenant/evidence/content-addressed keys, and
  must pass read-after-write byte-count and SHA-256 verification. PostgreSQL
  remains the metadata, policy, audit, review, retention, and deletion authority.
- The 8 MiB ceiling is fail-closed in runtime and domain code, S3 control
  responses are capped at 64 KiB, and duplicate immutable keys are rejected in
  both CI and local qualification.
- The local qualification command now starts PostgreSQL and S3-compatible
  object storage, exercises put/collision-rejection/read/verify/delete, and
  keeps the object store present during replica identity and failover checks.

## Gate 1 closure evidence

- The provider-neutral evidence-object increment passed the protected
  foundation, application, and immutable-release checks in PR #9 and was
  squash-merged to protected `main`.
- The supported clean-revision qualifier rebuilt the application image and
  proved the PostgreSQL 19 baseline, least-privileged role reconciliation,
  object create/collision rejection/read-after-write digest verification/delete,
  per-replica image and release identity, authenticated metrics, readiness, and
  four consecutive one-replica failover probes.
- The qualifier now handles expected native readiness failures without letting
  Windows PowerShell stderr records bypass bounded retries, and its HTTP probe
  remains non-interactive on Windows PowerShell 5.
- Gate 1 is therefore complete for the local/CI foundation. This is not a
  production-readiness or production-availability claim.

## Gate 2 verified progress

- The existing tenant and actor command context now governs the first
  `platform.workflow` vertical. Submitting party-onboarding evidence atomically
  opens one review task bound to the tenant, party identifier, exact party
  version, and `parties:approve` permission.
- Approval or hold requires and atomically completes that exact open task in
  the same command transaction as the party transition, command receipt, two
  append-only audit events, and two outbox events.
- Workflow rows use forced database row-level security, tenant-scoped locked
  reads, database lifecycle constraints, and optimistic locking. Cross-tenant
  and cross-subject task substitution, missing permission, stale state,
  consumed-task reuse, idempotent replay, and replay conflict are
  negative-tested.
- ADR-0011 records the bounded human-task model. General workflow definitions,
  assignment, delegation, escalation, cancellation, inbox queries, and
  notification delivery remain explicitly outside this increment.
- The `platform.integrations` connector-receipt vertical now atomically records
  one immutable outbound attempt and one versioned reconciled outcome with its
  command receipt, audit event, and outbox event. It does not perform network
  delivery or copy an external record.
- Request identity, governed subject/version, delivery identity, retry lineage,
  and server deadline are immutable. Outcome evidence is digest/reference only;
  raw remote responses are rejected. Only retryable or timed-out attempts can
  produce the next matching attempt.
- ADR-0012 records the receipt and recovery boundary. Named permissions,
  replay/conflict, duplicate delivery, immutable lineage, retry-after-success,
  timeout/recovery, stale state, raw-response rejection, tenant substitution,
  and forced row-level security are negative-tested.
- The application compiles with warnings as errors; 57 tests pass with one
  environment-gated test excluded; architecture-boundary and code-discipline
  checks pass for the connector increment.
- A complete security diff scan closed every changed production and migration
  file with no reportable finding. It reviewed permission/tenant boundaries,
  retry and deadline abuse, raw-content exclusion, transaction rollback,
  database constraints, and supply-chain impact.
- The `platform.agents` plan vertical now persists a server-digested, bounded
  acyclic step graph bound to one tenant, runbook identity, governed subject
  version, and exact human review task. Proposal and decision atomically include
  command receipts, audit events, and outbox events.
- Plan input rejects model, prompt, tool, endpoint, argument, and command fields.
  Approval or hold changes review state only; public responses, audit evidence,
  and events retain `execution_authorized: false`, and tests prove no connector
  receipt is created.
- ADR-0013 records this non-executing boundary. Named permissions, deterministic
  digest/duplicate protection, replay/conflict, invalid and cyclic graphs,
  stale state, exact-task/tenant substitution, consumed-task reuse, rollback,
  and forced row-level security are negative-tested.
- The application compiles with warnings as errors; 67 tests pass with one
  environment-gated test excluded; static analysis, the web security scan,
  architecture boundaries, and code discipline pass for the agent increment.
- A complete security diff scan closed all nine changed production and
  migration worklist rows with complete coverage and no reportable finding. It
  reviewed graph and input bounds, named permissions, tenant/subject/task
  substitution, stale and replay behavior, execution-field rejection,
  approval-to-execution separation, atomic rollback, database constraints, and
  supply-chain impact.

## Gate 2 closure evidence

- The governed human-task, connector-receipt, and non-executing agent-plan
  increments passed protected foundation, application, and release checks and
  were squash-merged through PRs #12, #13, and #14 as revisions
  `0c3c8e510575cdae5688a6a0116b5b90a9ceb512`,
  `456e7b678f756e9f69889ced728e2b2585b447e1`, and
  `2e96d88df67878d9b7023a49020487dfff2834ac`.
- On exact protected-main revision
  `2e96d88df67878d9b7023a49020487dfff2834ac`, compilation with warnings as
  errors, 67 application tests with one environment-gated test excluded,
  static analysis, the web security scan, and foundation, architecture,
  code-discipline, database, object-storage, external-identity, and web checks
  passed.
- The exact merged revision was rebuilt as immutable local image
  `babcfa8667e1aad4be24f6b6df6a44c34e94bb069b959dd669e772464d3d7174`.
  The qualifier proved the PostgreSQL 19 baseline and migrations,
  least-privileged role reconciliation, unsafe-role rejection, object
  create/collision rejection/read-after-write digest verification/delete,
  authenticated metrics, readiness and release identity, identical identity
  across two replicas, and four consecutive one-replica failover probes.
- The complete Gate 2 exit mapping, reproducible commands, residual risks, and
  rollback boundary are recorded in `docs/GATE_2_KERNEL_V0.md`.
- Gate 2 Kernel v0 is therefore qualified for local development and CI. This
  is not a production-readiness, production-availability, or completed
  user-facing business-operation claim.
- A final browser smoke identified and closed a local-only transport gap: the
  qualifier now proves that the shell is reachable through its loopback proxy,
  while negative configuration checks prove non-local hosts and production
  profiles still redirect to HTTPS.

## Gate 3 party-onboarding delivery evidence

- The first module-owned browser workspace now drives draft creation, bounded
  evidence upload, review-task visibility, and approve/hold decisions through
  the real versioned API. Tenant, actor, permissions, correlation, idempotency,
  and transitions remain server-owned.
- The isolated qualifier has a stable clone-local identity and high-entropy
  access code protected by restrictive operating-system ACLs. Successful login
  returns an eight-hour opaque, database-revocable bootstrap session; invalid credentials, forged
  tokens, and production-profile activation fail closed. This is not the
  production identity selection.
- `platform.evidence` now owns persisted tenant/subject metadata with forced
  row-level security, immutable object identity, bounded classifications and
  content types, exact size and SHA-256, a pending/verified lifecycle, and a
  digest-only storage receipt.
- Evidence upload is a recoverable prepare/store/verify sequence. The object
  key is server-derived, byte storage is create-only and read-after-write
  verified, and a retry after storage verifies the existing object instead of
  overwriting or deleting it.
- New uploads require a server-owned permission, tenant, party lifecycle, and
  expected-version preflight before file bytes are read or persisted. Exact
  verified replays skip the upload path and reach the idempotent party command;
  the final mutation repeats validation under a row lock.
- Party evidence submission now fails unless the evidence record is verified,
  belongs to the tenant, and is bound to the exact party. The resulting review
  task remains subject/version-bound and is consumed atomically with party
  decision, receipt, audit, and outbox state.
- Open-task queries require an inbox permission and return only tasks whose
  recorded decision permission is held by the actor. The API publishes its
  versioned machine-readable contract.
- Tests cover the complete API journey and replay plus invalid login,
  forged token, missing authorization, stale state, unsupported upload, tenant
  and subject substitution, forced row-level security, retry recovery, zero
  persistence for unknown/stale subjects, and ownership-safe cleanup after
  object verification failure.
- A complete security diff review first validated three low-severity findings:
  pre-existing-object cleanup ownership, access-code receipt output, and upload
  persistence before party preflight. All three were corrected and regression
  tested. The post-remediation review closed 80 of 80 inventory items with zero
  findings and no deferred proof gaps. Backend quality passed 83 tests with one
  live-object-store test reserved for deployment; frontend quality passed four
  files and five tests; static security, architecture, database, object-store,
  identity, credential ACL, artifact-integrity, and advisory checks passed.
- Exact candidate revision `79f5813eb2769ed2db18f01b360ab9ead9724c76`
  was rebuilt as immutable local image
  `3d823ddcbf63ce5b92f9f0cf18940c930839ad8067bc9625362062e3568eeeb5`.
  The qualifier proved PostgreSQL 19 startup and migrations, the real object
  create/collision/read-after-write/delete path, identical identity across two
  replicas, four one-replica failover probes, and the authenticated
  create/evidence/replay/task/approval/final-read journey.
- Rendered qualification passed at 1440-by-900 and 390-by-844 through the local
  proxy. Both viewports had no page-level horizontal overflow or browser
  console warnings/errors; primary brand and navigation targets were at least
  44 pixels, and the mobile party list collapsed to content height. The final
  responsive patch received a separate complete security review with zero
  findings and no deferred proof gaps.
- ADR-0014 records the identity, evidence choreography, recovery, API, and UI
  boundaries.
- Protected foundation, application, and immutable-release checks passed in
  PR #17, which was squash-merged to `main` as
  `cd6c6415dc58132f7d7941509fa3c7202d0ed5ea`. That exact protected revision
  was rebuilt as image
  `2619d9f336a0acbfc4bffac4df08e6296ab240420f28a8898ff0b3dbaf98bb18`.
  Database and object-storage qualification, identical two-replica identity,
  four one-replica failover probes, the authenticated end-to-end business
  flow, and rendered desktop/mobile smoke all passed again. The first Gate 3
  vertical is delivered; this is necessary evidence, not the complete Gate 3
  exit.

## Gate 3 product-sourcing delivery evidence

- `master.products`, `master.locations`, and `trade.sourcing` now own separate
  tenant-safe records. Product and location references are active bounded
  commands; a sourcing lane binds an approved supplier, active product, and
  distinct active route endpoints without copying master data.
- Lane evidence uses the delivered immutable evidence boundary. Submission
  opens one exact version-bound review task; approve or HOLD atomically consumes
  that task with command receipt, audit, outbox, and lane transition state.
  Resubmission after HOLD clears the prior decision metadata, requires fresh
  verified evidence, and opens a new exact task. Reuse of the consumed task is
  rejected and regression-tested.
- Forced row-level security, composite tenant foreign keys, lifecycle
  constraints, server-owned permissions, stable identifiers, optimistic
  concurrency, idempotent replay/conflict behavior, and cross-tenant/reference/
  task substitution failures are executable database and application tests.
- Candidate revision `070e3e2017c46b1eb97ee06f31766ae14e1b2929` was
  rebuilt as local image
  `ec0caef994db82be4660acb6d35a0bd7458da8d70d9d26256ba020ccd0fb4da6`.
  The supported qualifier proved PostgreSQL 19 startup and migrations,
  least-privileged role reconciliation, real immutable evidence-object
  create/collision/read-after-write/delete, the authenticated approved-party/
  product/two-location/lane/evidence/task/approval/final-read journey,
  identical identity across two replicas, and four one-replica failover probes.
- Rendered candidate proof at 1440-by-900 and 390-by-844 found no horizontal
  overflow or console warnings/errors. Navigation, primary actions, and lane
  controls remained at least 44 pixels high. The desktop shell spans the full
  viewport and gives the sourcing work area a 1,053-pixel governed canvas.
- Backend quality passed 91 tests with one live-object-store test reserved for
  deployment. Frontend quality passed five files and six tests. Formatting,
  dual type checks, linting, compilation with warnings as errors, static
  analysis, dependency audits, architecture, code discipline, database,
  object-store, external-identity, credential-ACL, production-configuration,
  and artifact-integrity checks passed.
- The first sealed security review found one low-severity HOLD-resubmission
  lifecycle defect, which was corrected and regression-tested. The final
  immutable revision-range review inspected all 50 changed files, deferred
  none, and reported zero findings, but its finalizer could not seal the report
  because required snapshot-digest metadata was absent. ADR-0016 records the
  product owner's explicit waiver for that artifact-sealing defect only. The
  absence of a canonical sealed post-fix bundle remains a disclosed residual
  risk; protected CI, review, security, and exact-revision release gates are not
  waived.
- ADR-0015 records the module ownership, command, evidence, workflow, API,
  recovery, and RFQ-exclusion boundaries for the delivered increment.
- Protected foundation, application, and immutable-release checks passed in
  PR #19, which was squash-merged to `main` as
  `6628b49626ad618286b6cacc8034ce789b9b5e03`. That exact protected revision
  was rebuilt as image
  `9fcefd4f0cf011b830c956770088e42b969b004c280e1f0a688a305f007b6905`.
- Exact merged-revision qualification passed PostgreSQL 19 startup and all
  migrations, least-privileged role reconciliation, unsafe-role rejection,
  immutable evidence-object create/collision/read-after-write/delete, the
  authenticated party/product/two-location/lane/evidence/replay/exact-task/
  approval/final-read flow, identical identity across two replicas, and four
  one-replica failover probes. It created qualified product
  `7fc840cd-f93d-4f88-a296-92b8bc038280` and lane
  `78458e59-5d23-4188-8786-b8cc0f19f9a8`.
- The exact merged UI route returned HTTP 200. At 1440-by-900 the sourcing
  workspace occupied 1,069 pixels of the governed desktop canvas; at
  390-by-844 it collapsed to the 375-pixel document width. Neither viewport
  had horizontal overflow or an interactive target below 44 pixels.
- The second Gate 3 vertical is delivered. Gate 3 remains active because RFQ
  and quote comparison, commitment proposal, shipment readiness, and governed
  reporting have not yet passed equivalent end-to-end evidence.

## AI-compatible kernel and module-neutrality decision

- A read-only assessment of protected revision
  `529ae395d47ee5862325d13d8936ffe3935a1b70` found no business-module or HTTP
  dependency in the backend kernel. Business modules depend inward on generic
  command, tenant, idempotency, audit, outbox, health, and release primitives.
  Architecture-boundary verification passed for 66 source files,
  code-discipline verification passed for 127 production files, and foundation
  verification retained an acyclic graph of 19 modules with 95 uniquely owned
  record types.
- Current cross-module production imports use declared `Public` contracts, but
  source imports are not yet mechanically reconciled with the module catalog.
  The shared UI shell and application composition also contain static Party and
  Sourcing navigation. These are disclosed installability gaps, not backend
  kernel-policy leakage.
- ADR-0017 establishes that the kernel deterministically governs AI instead of
  embedding probabilistic authority. Prompt text, retrieved content, model
  output, persistent context, and tool responses are untrusted and advisory.
  Future agent execution requires server-owned runbooks, narrow delegated
  identity, typed tools, fresh command authorization, memory isolation,
  provenance, budgets, evaluations, incident controls, and recovery.
- ADR-0018 assigns module manifests, compatibility, tenant enablement, surface
  registration, and verification receipts to `platform.modules`. It requires
  source-to-catalog dependency enforcement, module-owned migration metadata,
  registry-derived UI surfaces, kernel-only boot, and disabled-module boot
  before installable sub-app independence is claimed.
- These are accepted target decisions, not implemented capability. ADR-0013's
  non-executing plans remain the only delivered agent surface, and the current
  compiled static module composition remains the supported Gate 3 release.

## Gate 3 RFQ and quote-comparison delivery evidence

- `trade.sourcing` now has a delivered requisition, RFQ invitation, supplier
  quote, and quote-comparison vertical. Requisitions bind an exact approved
  sourcing-lane version and product base unit. RFQs bind an exact requisition
  transition, one settlement currency, a future response deadline, and two to
  twenty distinct approved supplier Party versions.
- Supplier quotes are accepted only for invited approved suppliers, the exact
  requisition quantity, and RFQ currency. A draft becomes submitted only after
  verified evidence bound to the exact quote is available through the existing
  immutable evidence boundary.
- Comparison creation requires at least two submitted quotes. While the
  response deadline is open, every invited supplier must have submitted;
  afterward, the two-response floor applies. The check and transition share
  the RFQ lock, close the RFQ against further quotes, and store a versioned
  deterministic ranking snapshot ordered by total price, delivery days, and
  stable identifier. The server owns the recommendation; the UI and request
  cannot submit it.
- One exact comparison-version human task governs approve or HOLD. The decision
  atomically updates the comparison and RFQ with command receipt, append-only
  audit, and outbox events. It does not create a purchase commitment or any
  external side effect.
- Five tenant tables have composite tenant references, forced row-level
  security, bounded decimals, lifecycle constraints, uniqueness, and
  optimistic locking. The local qualification identity gained only the ten
  named permissions required by this slice.
- Backend tests cover the complete public/API flow, replay,
  deterministic ranking, premature-close rejection, stale decision, missing
  permission, cross-tenant and non-invited supplier substitution, insufficient
  submitted quotes, evidence binding, exact task, and persistence. The
  captured security diff review found the premature-close weakness and the
  delivered implementation remediates it with the deadline/invitation
  invariant.
  Frontend type checks, lint, unit tests, and production build cover the new
  RFQ/comparison workspace.
- Exact candidate revision `d9d400a360b042887f43537696f48cda4253c82b`
  was rebuilt as immutable local image
  `8808475b8ca83754bd14db081f67efa378d5c300563f17cafa6222274feda8e5`.
  The first runtime attempt exposed missing least-privilege grants for the five
  new tenant tables; the grants, exact-grant verifier, and database-policy
  regression were corrected before this successful run. The clean-revision
  qualifier then passed PostgreSQL 19 startup and all migrations,
  least-privileged role reconciliation and unsafe-role rejection, immutable
  evidence-object create/collision/read-after-write/delete, the authenticated
  requisition/RFQ/two-quote/evidence/deterministic-comparison/exact-task/
  approval journey, identical image and release identity across two replicas,
  and four one-replica failover probes. It created qualified RFQ
  `a0a4a299-64b6-4900-98bb-ba9e19f65630` and comparison
  `47f41d4d-f930-43ff-8f7f-3092fb1fd863`.
- Rendered candidate proof passed at 1440-by-900 and 390-by-844. The RFQ
  workspace used a 1,053-pixel desktop canvas and a 338-pixel mobile canvas;
  both viewports had no horizontal overflow, no visible interactive control
  below 44 pixels, and no browser warning or error. The deployed comparison
  was visibly `approved` with the lower total price ranked first.
- Protected PR #22 passed Foundation, Application, and Release checks and was
  squash-merged to protected `main` as exact revision
  `95ca2a36b4e2906fc63c32268e71f94be3dc2f87`.
- The exact merged revision was rebuilt as local image
  `a436e63b1732268853901c3e291f33505ed5e04e4fc8aee100a0a4882b7bf898`.
  The supported qualifier repeated PostgreSQL 19 startup and migrations,
  least-privileged role reconciliation and unsafe-role rejection, immutable
  evidence-object create/collision/read-after-write/delete, the authenticated
  requisition/RFQ/two-quote/evidence/deterministic-comparison/exact-task/
  approval journey, identical image and release identity across two replicas,
  and four one-replica failover probes. It created qualified RFQ
  `20cee897-2d1e-4bc1-bdb0-f1d49f398bee` and comparison
  `5740bd95-dd29-4aba-9042-1487b2793269`.
- Rendered exact-merge proof repeated the desktop and mobile checks with no
  horizontal overflow, sub-44-pixel visible control, browser warning, or
  browser error; the approved deterministic ranking remained visible.
- ADR-0019 records the ownership, attribution, formula, evidence, approval,
  commitment-exclusion, and recovery boundaries. The third sequential Gate 3
  vertical is therefore delivered. Gate 3 itself remains active because the
  commitment, shipment-readiness, governed-reporting, jobs, and recovery exit
  evidence is not complete.

## Gate 3 purchase-commitment proposal delivered

- ADR-0020 assigns `purchase_commitment_proposal` to `trade.contracts` as an
  internal, non-binding proposal. It accepts one exact approved comparison and
  derives all commercial terms and lineage through the public sourcing
  contract; clients cannot submit supplier, quantity, price, currency,
  delivery, recommendation, or evidence fields.
- The delivered vertical implements authenticated create/list, bounded evidence
  upload, exact human approve/HOLD, optimistic concurrency, idempotency, atomic
  audit and outbox records, forced tenant row-level security, composite source
  references, and a single decision workspace. Every response, audit, and
  event explicitly records that no commitment or external effect was created.
- The workflow benchmark preserves the proven separation between source
  selection, internal approval, and downstream issuance while removing term
  re-entry and cross-document navigation. `docs/ENGINEERING_STANDARDS.md` now
  requires a measurable, product-neutral outcome benchmark for every future
  feature without weakening security, accessibility, audit, or recovery.
- Focused backend/API/OpenAPI tests pass, including permission denial, tenant,
  source, evidence and task substitution, stale comparison/RFQ/quote state,
  client term injection, duplicate proposal, replay, HOLD recovery, and proof
  of no connector receipt. The completed 29-file security diff review found no
  reportable vulnerability; its one non-reportable RFQ-version hardening
  observation was corrected and regression-tested before delivery.
- The frontend passes formatting, linting, current and compatibility type
  checks, eight tests, and a production asset build. The full backend quality
  gate passes 100 tests with one object-store integration test reserved for the
  immutable runtime qualifier; dependency and policy verifiers are clean.
- The first protected application check exposed an exact least-privilege
  verifier allowlist that had not advanced with the four new proposal
  permissions. Commit `262b467f5c63e9eacaaea735eac1f17a4a358b03`
  corrected only that verifier contract; its production-profile reproduction,
  complete local quality gate, and all three protected checks passed.
- Pull request #24 merged through protected review as
  `bdf2dbfe3423e46302205ea3e435ccfa94da7e13`. The exact candidate and exact
  merged revision each passed the immutable two-replica PostgreSQL/object-store
  journey, source-derived proposal/evidence/exact-approval/final-read checks,
  explicit no-downstream/no-external-effect assertions, and four
  single-replica failover probes.
- The exact merged image is
  `67e98110607c4fa09f1f82d1f19894bbb1095d7c7e210dc5ed2281ef914a0f12`
  on both replicas. It created proposal
  `43d669c3-9658-4178-9b20-1230f6e73195` and remains ready at the isolated
  local qualification endpoint.
- Rendered exact-merge desktop and 390-by-844 mobile checks show the approved
  source terms, evidence lineage, and false side-effect boundary with no page
  overflow, browser warning, or browser error; visible mobile actions remain
  above 44 pixels. The fourth sequential Gate 3 vertical is therefore
  delivered, while Gate 3 remains active.

## Gate 3 shipment-readiness delivered

- ADR-0021 assigns `shipment_readiness_case` to `trade.shipments` as a
  non-executing gate over one exact approved purchase-commitment proposal. The
  server derives the complete commercial source and versioned checklist;
  clients can select only the proposal, attach one exact case-bound evidence
  bundle, and submit GO or HOLD.
- The delivered vertical implements authenticated create/list, strict
  server-owned fields, bounded evidence preflight and upload, exact human tasks,
  GO/HOLD, HOLD resubmission recovery, idempotency, optimistic concurrency,
  atomic audit and outbox records, a composite tenant source reference, and
  forced row-level security. Every response, audit, and event keeps shipment,
  dispatch, inventory, finance, and external-effect flags false.
- The product-neutral benchmark preserves the proven separation between
  readiness and later execution while reducing the operator path to three
  actions, zero commercial-term re-entry, and zero cross-document navigation.
  Shipment planning, booking, dispatch, inventory, finance, or connector work
  remains outside this authority.
- Backend quality passes 105 tests with one object-store integration test
  reserved for the immutable runtime qualifier. Frontend formatting, lint,
  current and compatibility type checks, ten tests, and production build pass.
  Architecture, code-discipline, database, object-storage, external-identity,
  web-foundation, dependency-advisory, and package-vulnerability checks pass.
- The sealed security diff review completed all 27 changed production-source
  worklist rows with no reportable finding. It traced authentication and named
  permissions, tenant/RLS scope, current-source and task/evidence binding,
  stale/replay/concurrency behavior, upload bounds, atomic receipt/audit/outbox
  behavior, and the explicit no-downstream-effect boundary.
- Protected PR 26 passed foundation, application, and release checks and was
  squash-merged as exact revision
  `d64047f65b1a2061d7a0c03669407ab1779b305b`.
- The exact merged image `localhost/uok-next:d64047f65b1a` has identity
  `790e85155f64f0f1ea33a7a2606f680e8511f84e7fc0e7b83a1203f8b092e6f5`
  on both replicas. PostgreSQL 19, object storage, the complete authenticated
  party-to-readiness journey, shipment-readiness case
  `262e6926-b248-4141-98eb-48c272111249`, and four single-replica failover
  probes passed.
- Rendered exact-merge proof at the default 1280-by-720 desktop viewport and a
  390-by-844 mobile viewport found no page overflow, browser warning, browser
  error, or visible action below 44 pixels. The source handoff and GO boundary
  are visible at both sizes, and the mobile module rail retains touch scrolling
  without exposing a native scrollbar. The fifth sequential Gate 3 vertical is
  therefore delivered, while Gate 3 remains active.

## Gate 3 governed operational reporting merged and runtime-qualified

- Accepted ADR-0023 assigns the non-persisted
  `operational_report_projection` to `intelligence.bi`. The report consumes one
  exact tenant-owned shipment-readiness case and its current authoritative
  source chain through module public queries inside one PostgreSQL
  repeatable-read, read-only transaction; it creates no analytical copy,
  command authority, task, connector call, or external effect.
- The authenticated API and workbench require `reports:operational:read` plus
  every source-read permission. Exact readiness version, current-source
  validation, tenant predicates, forced row-level security, bounded audit and
  outbox lineage, no-store responses, deterministic reconciliation, failure
  clearing, and explicit false authority flags all fail closed.
- Backend quality passes 119 tests with one object-store integration test
  reserved for the immutable runtime qualifier. Frontend formatting, lint,
  TypeScript 7 and 6 compatibility, 14 tests, and the production build pass.
  Architecture, code-discipline, database, object-storage, external-identity,
  web-foundation, production-security, local-qualification-security,
  dependency-advisory, and package-vulnerability checks pass.
- The sealed security diff review completed all 30 changed source worklist rows
  with no reportable finding. It traced authentication and named permissions,
  tenant/RLS scope, exact source/version binding, repeatable-read and read-only
  behavior, lineage bounds and privacy, deterministic reconciliation,
  telemetry, request bounds, and the no-business-mutation boundary.
- Protected PR 34 passed foundation, application, and release checks and was
  squash-merged as exact revision
  `204ea3624def671d7aa6c475485e75adc5ba9071`.
- The exact merged image `localhost/uok-next:204ea3624def` has identity
  `8f5ccc3121803e35ccd62dd8a1d3bd37c13d26eacd0ea3a76af16d620f6b5d56`
  on both replicas. PostgreSQL 19, object storage, the complete authenticated
  party-to-readiness journey, deterministic report projection
  `2913efff7f9196b657ef8c4ed7bd6349717b036c1e35ad1e375d0c0b00eda695`,
  and four single-replica readiness, release, and report probes passed.
- The loopback browser shell returned HTTP 200, but exact-merge rendered
  desktop/mobile capture remains blocked because the Codex in-app browser
  could not verify its admin-enforced access policy. The reporting vertical is
  merged and runtime-qualified but is not yet recorded as delivered until that
  visual gate passes.

## Gate 3 local attributable-user increment verified in source

- Accepted ADR-0024 keeps the clone-local access code as bootstrap
  administration and adds tenant-owned regular users under `platform.identity`.
  Two allowlisted party-onboarding profiles replace browser-supplied
  permissions with server-owned access grants.
- Administrators create pending users with temporary passwords. First login is
  restricted to password replacement; activation rotates credential generation
  and revokes every earlier session before business permissions can be issued.
- Password verifiers are versioned, salted, and deliberately expensive. Opaque
  session secrets and login identifiers are retained only as digests.
  PostgreSQL-backed throttling is serialized per tenant and identifier across
  both application replicas. Unknown usernames share one bounded bucket and
  the login boundary rejects non-JSON bodies. Authentication errors remain
  uniform.
- Users, credential verifiers, regular sessions, bootstrap sessions, and
  throttles have tenant
  references, forced row-level security, bounded constraints, and negative
  isolation tests. Plaintext temporary and activated passwords are absent from
  users, credentials, sessions, command receipts, audits, and outbox events.
- Backend quality passes 126 tests with one object-store integration test
  reserved for the immutable runtime qualifier. Frontend formatting, lint,
  TypeScript 7 and 6 compatibility, 19 tests, and the production build pass.
  Architecture, code-discipline, database, object-storage, external-identity,
  web-foundation, production/local security-configuration, static-security,
  and dependency-advisory checks pass.
- The first sealed security diff found two low-severity local-qualification
  defects: distinct unknown usernames could grow throttle state and admit
  expensive verification, and bootstrap sign-out did not revoke its stateless
  bearer. The remediation now rejects non-JSON login, uses one bounded unknown
  bucket, persists bootstrap sessions by digest, revokes them server-side, and
  keeps browser state when revocation is not confirmed. Focused trigger and
  legitimate-path tests pass. Post-fix security scan
  `f8573597-572d-45b4-bfe1-6810f41502b9` reviewed all 56 selected changed
  files across nine security surfaces and sealed with zero findings.
  Architecture, code-discipline, database, object-storage, external-identity,
  web-foundation, static-security, and dependency-advisory checks pass.
- Clean candidate revision `0440d50d884c659147fd74b230c2ef4765fe22d5`
  rebuilt as immutable image
  `a3894e6dd278103591c431d66f9bbad67def172b1d9f42a931a0ebd70e15e63c`
  on both replicas. PostgreSQL 19 migrations and role reconciliation, object
  storage, the complete Gate 3 business chain, authenticated metrics, release
  identity, and four single-replica readiness/release/report probes passed.
- Regular user `entity.operator` was provisioned through the administrator API,
  forced through temporary-password activation, signed in with the rotated
  credential, and created draft party
  `0ac0cb27-818e-4a21-b893-aa2c0ae2f808`. Its server-owned profile exposes only
  evidence and party-onboarding permissions; the generated credential is in
  clone-local, ACL-restricted storage outside the repository.
- Protected PR #36 remains open. GitHub recorded open, reopen, and synchronize
  attempts, but its action scheduler has not created the required foundation,
  application, or release jobs. Administrative bypass is prohibited, so merge
  and exact-merge qualification remain blocked on those external checks.
- The browser shell returns through the loopback proxy, but rendered
  desktop/mobile automation remains blocked because the in-app browser cannot
  currently verify its admin-enforced access policy. This section therefore
  records a qualified candidate, not a delivered increment.

## Explicitly not yet implemented

- Production identity/federation, production session and recovery policy,
  invitation delivery, multifactor/passkey enrollment, account suspension
  administration, binding purchase contract or order formation and business
  APIs beyond the proposal boundary, durable outbox delivery, scheduled jobs,
  general workflow
  definitions, task assignment/delegation/escalation/notification, evidence
  malware scanning/promotion/retention/deletion, live connector transport and
  credential/retry scheduling, server-owned agent runbook definitions,
  model/tool execution, agent scheduling/budgets, persisted or cross-operation
  BI projections, or evidence anchoring.
- Module installation, tenant enablement, compatibility enforcement, dynamic
  surface registration, source-to-catalog import reconciliation, module-owned
  migration receipts, kernel-only boot qualification, disabled-module boot
  qualification, persistent agent memory, delegated agent capabilities, tool
  authorization, agent evaluations, or agent incident controls.
- The local two-replica qualifier is not a production topology. PostgreSQL 19
  is still a single local dependency and no backup/restore receipt exists.
- Production deployment is blocked on a selected platform, managed secrets,
  trusted TLS ingress, monitoring/alerting destinations, backup/restore,
  rollback, capacity, penetration, and disaster-recovery qualification.

## Next action

Allow PR #36's required protected checks to run, merge only after all three
pass, and repeat qualification on the exact merged revision. Then render the
regular-user and operational-report flows at 1280-by-720 and 390-by-844 with no
overflow, browser warning/error, inaccessible control, or visible action below
44 pixels. Continue Gate 3 with durable outbox delivery, scheduled jobs, and
recovery evidence only after those exit criteria pass.

AI execution and module-installation implementation remain deferred. This
status advance does not create a second active delivery focus.
