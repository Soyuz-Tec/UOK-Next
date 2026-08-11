# ADR-0008: React and TypeScript delivery foundation

**Status:** Accepted

**Date:** 2026-08-11

## Context

ADR-0001 selected React and TypeScript for UOK Next user surfaces, and ADR-0005
selected one web workspace in the modular monolith. Gate 1 still lacked an
executable UI boundary, a reproducible frontend toolchain, tests, supply-chain
checks, and a decision about how browser artifacts enter the release.

The UI must eventually serve internal, partner, public, and field users without
becoming a second policy engine. Adding a separate frontend deployment, runtime
server, state framework, or design system before a proven consumer would expand
failure and security boundaries without business evidence.

## Decision

- Use one npm workspace under `web/`, with exact dependency versions and an npm
  v11 lockfile. Node 24.19.0 LTS and npm 11.17.0 are the governed build runtime.
- Use React 19.2.8 and React DOM 19.2.8 for presentation, Vite 8.2.1 for the
  production build and development server, and Vitest for component/contract
  tests.
- Use the stable native TypeScript 7.0.2 compiler for the authoritative type
  check. Keep `@typescript/typescript6` 6.0.2 as a development-only compatibility
  API for ecosystem tooling that has not yet moved to the native compiler API;
  both compilers must pass.
- Compile content-hashed static assets into `priv/static/uok-ui` and copy them
  into the same immutable Phoenix release image. Phoenix serves the shell at
  `/` and assets under `/uok-ui/`; APIs remain same-origin under `/api/v1`.
- The `web/src/shell` layer is module-neutral and cannot import module UI code.
  Future business UI belongs under `web/src/modules/<module-id>` and must use
  server-owned commands and query contracts.
- The browser never owns authorization, approval, tenant, audit, evidence,
  idempotency, or business-state transition policy. The initial shell performs
  one read-only readiness check and exposes no business mutation.
- The shell response uses a restrictive content security policy, denies
  framing and unnecessary browser capabilities, and loads no runtime assets
  from external origins.
- CI runs format, lint, native and compatibility type checks, unit tests,
  production build, npm advisory audit, architecture policy, and the immutable
  release build. The Node build image and GitHub Action are digest/commit pinned.
- Client routing, server-side rendering, a state library, component framework,
  module federation, and PWA/offline mutation are deferred until a Gate 3
  business operation supplies an explicit consumer and security contract.

## Consequences

The initial UI has one dependency graph, one release identity, and no new
production process or cross-origin trust boundary. The production image is
slightly more complex because it has a separate, pinned Node build stage, but
the runtime image contains only the compiled assets and the existing non-root
Phoenix release.

The TypeScript 6 compatibility package temporarily duplicates compiler tooling.
It must be removed when all lint/test tooling supports the native TypeScript 7
API. Exact pins require deliberate dependency-review increments rather than
ambient version drift.

## Alternatives considered

- Separate static hosting or a Node production server: rejected for Gate 1
  because it creates another deployable unit, origin, cache, and release-identity
  problem without a measured scaling requirement.
- Phoenix LiveView as the primary UI: rejected because the accepted product
  surfaces include field/PWA and specialist interactions already assigned to
  React; LiveView remains available for bounded operational tooling if justified.
- Next.js or another meta-framework: deferred because routing, SSR, and server
  rendering are not needed by the module-neutral foundation shell.
- A runtime CDN for fonts or scripts: rejected to keep the initial content
  policy and supply chain self-contained.
- TypeScript 6 only: rejected because TypeScript 7 is stable and materially
  improves compiler throughput; the compatibility package is bounded to tools.

## Validation

- `npm run quality` proves formatting, linting, both type checks, component and
  trust-boundary tests, and a production Vite build;
- architecture checks reject shell imports from business-module UI paths and
  external runtime asset references;
- Phoenix controller tests prove the compiled shell response and restrictive
  headers;
- the container build proves the lockfile-driven web stage is copied into the
  same non-root release image;
- rendered desktop and phone-width smoke evidence is required before delivery.
