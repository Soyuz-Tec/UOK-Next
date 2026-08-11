import { usePlatformStatus } from "./usePlatformStatus";

const foundationAreas = [
  {
    eyebrow: "Kernel",
    title: "Governed command path",
    detail:
      "Tenant context, permissions, idempotency, audit evidence, and outbox state stay server-owned.",
    state: "Qualified",
  },
  {
    eyebrow: "Data platform",
    title: "PostgreSQL 19",
    detail:
      "Row-level tenant isolation and bounded runtime roles are active in the local qualifier.",
    state: "Qualified",
  },
  {
    eyebrow: "Evidence boundary",
    title: "Evidence object storage",
    detail:
      "A local S3-compatible qualifier now proves bounded, content-addressed, quarantined object bytes.",
    state: "Qualified",
  },
] as const;

const moduleGroups = [
  "Master data",
  "Trade execution",
  "Operations work",
  "Evidence & audit",
  "Business intelligence",
  "External systems",
] as const;

export function AppShell() {
  const platformStatus = usePlatformStatus();

  return (
    <div className="app-frame">
      <a className="skip-link" href="#main-content">
        Skip to main content
      </a>

      <header className="topbar">
        <a className="brand" href="#overview" aria-label="UOK Next home">
          <span className="brand-mark" aria-hidden="true">
            U
          </span>
          <span>
            <strong>UOK Next</strong>
            <small>Evidence-first operations</small>
          </span>
        </a>
        <div className={`health-pill health-pill--${platformStatus.phase}`} aria-live="polite">
          <span className="health-dot" aria-hidden="true" />
          {platformStatus.label}
        </div>
      </header>

      <aside className="sidebar" aria-label="Platform navigation">
        <nav>
          <a className="nav-link nav-link--active" href="#overview" aria-current="page">
            <span className="nav-icon" aria-hidden="true">
              01
            </span>
            Foundation
          </a>
          <a className="nav-link" href="#module-map">
            <span className="nav-icon" aria-hidden="true">
              02
            </span>
            Module map
          </a>
          <a className="nav-link" href="#release-boundary">
            <span className="nav-icon" aria-hidden="true">
              03
            </span>
            Release boundary
          </a>
        </nav>
        <div className="gate-card">
          <span className="eyebrow eyebrow--light">Active focus</span>
          <strong>Gate 2</strong>
          <p>Kernel v0</p>
          <div className="progress-track" aria-label="Gate 2 kernel progress">
            <span />
          </div>
        </div>
      </aside>

      <main id="main-content">
        <section className="hero" id="overview" aria-labelledby="hero-title">
          <div>
            <span className="eyebrow">Operational foundation</span>
            <h1 id="hero-title">One trusted path from decision to evidence.</h1>
            <p className="hero-copy">
              The shell exposes platform readiness without taking business authority away from the
              Elixir kernel. Modules arrive only when their policies, ownership, and recovery path
              are proven.
            </p>
          </div>
          <div className="readiness-card">
            <div className="readiness-head">
              <span
                className={`readiness-symbol readiness-symbol--${platformStatus.phase}`}
                aria-hidden="true"
              />
              <span>
                <small>Runtime contract</small>
                <strong>{platformStatus.label}</strong>
              </span>
            </div>
            <p>{platformStatus.detail}</p>
            <dl>
              <div>
                <dt>UI authority</dt>
                <dd>Presentation only</dd>
              </div>
              <div>
                <dt>Business policy</dt>
                <dd>Server enforced</dd>
              </div>
              <div>
                <dt>Release model</dt>
                <dd>One artifact</dd>
              </div>
            </dl>
          </div>
        </section>

        <section className="section-block" aria-labelledby="foundation-title">
          <div className="section-heading">
            <div>
              <span className="eyebrow">Current evidence</span>
              <h2 id="foundation-title">Foundation at a glance</h2>
            </div>
            <span className="truth-label">No production claim</span>
          </div>
          <div className="foundation-grid">
            {foundationAreas.map((area) => (
              <article className="foundation-card" key={area.title}>
                <span className="eyebrow">{area.eyebrow}</span>
                <h3>{area.title}</h3>
                <p>{area.detail}</p>
                <span className="card-state">{area.state}</span>
              </article>
            ))}
          </div>
        </section>

        <section
          className="section-block module-section"
          id="module-map"
          aria-labelledby="modules-title"
        >
          <div className="section-heading">
            <div>
              <span className="eyebrow">Bounded architecture</span>
              <h2 id="modules-title">Module map</h2>
            </div>
            <p>Visible boundaries, deliberately inactive.</p>
          </div>
          <div className="module-list">
            {moduleGroups.map((moduleName, index) => (
              <div className="module-row" key={moduleName}>
                <span className="module-number">{String(index + 1).padStart(2, "0")}</span>
                <strong>{moduleName}</strong>
                <span>Reserved</span>
              </div>
            ))}
          </div>
        </section>

        <section className="boundary-banner" id="release-boundary" aria-labelledby="boundary-title">
          <div>
            <span className="eyebrow eyebrow--light">Release boundary</span>
            <h2 id="boundary-title">React is compiled into the Phoenix release.</h2>
          </div>
          <p>
            One lockfile, immutable hashed assets, same-origin APIs, and a restrictive content
            security policy keep the initial delivery boundary small and inspectable.
          </p>
        </section>
      </main>
    </div>
  );
}
