import { useCallback, useEffect, useState } from "react";

import {
  listShipmentReadinessCases,
  type ShipmentReadinessCase,
} from "../trade-shipments/readinessApi";
import {
  getOperationalReport,
  type OperationalReport,
  type ReportAuditEvent,
  type ReportEvidence,
} from "./operationalReportApi";

type Props = { token: string; tenantId: string; onSignOut: () => void };

export function OperationalReportWorkspace({ token, tenantId, onSignOut }: Props) {
  const [cases, setCases] = useState<ShipmentReadinessCase[]>([]);
  const [selection, setSelection] = useState("");
  const [report, setReport] = useState<OperationalReport>();
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState<string>();

  const loadReport = useCallback(
    async (readiness: ShipmentReadinessCase) => {
      setBusy(true);
      setError(undefined);
      setReport(undefined);

      try {
        setReport(await getOperationalReport(token, readiness.id, readiness.lock_version));
      } catch (reason) {
        setError(message(reason));
      } finally {
        setBusy(false);
      }
    },
    [token],
  );

  useEffect(() => {
    let active = true;

    void listShipmentReadinessCases(token)
      .then(async (items) => {
        if (!active) return;
        const reportable = items.filter((item) => item.status === "go" || item.status === "hold");
        setCases(reportable);

        const latest = reportable[0];
        if (latest === undefined) {
          setBusy(false);
          return;
        }

        setSelection(latest.id);
        await loadReport(latest);
      })
      .catch((reason: unknown) => {
        if (!active) return;
        setReport(undefined);
        setError(message(reason));
        setBusy(false);
      });

    return () => {
      active = false;
    };
  }, [loadReport, token]);

  function selectReport(id: string) {
    setSelection(id);
    const readiness = cases.find((candidate) => candidate.id === id);
    if (readiness !== undefined) void loadReport(readiness);
  }

  function retry() {
    const readiness = cases.find((candidate) => candidate.id === selection);
    if (readiness !== undefined) void loadReport(readiness);
  }

  return (
    <section className="operational-report" id="operational-report" aria-labelledby="report-title">
      <header className="workspace-heading">
        <div>
          <span className="eyebrow">Gate 3 · governed operational intelligence</span>
          <h1 id="report-title">See the complete decision chain in one trusted view.</h1>
          <p>
            Tenant {tenantId.slice(0, 8)}… · live source data, attributable evidence, zero business
            mutation authority.
          </p>
        </div>
        <button className="button-secondary" type="button" onClick={onSignOut}>
          Sign out
        </button>
      </header>

      <section className="report-picker" aria-labelledby="report-picker-title">
        <div>
          <span className="eyebrow">Automatic latest report</span>
          <h2 id="report-picker-title">Readiness outcome</h2>
          <p>A different completed case is one selection. No source field is re-entered.</p>
        </div>
        <label>
          Report case
          <select
            value={selection}
            disabled={cases.length === 0 || busy}
            onChange={(event) => selectReport(event.target.value)}
          >
            {cases.length === 0 ? <option value="">No completed readiness case</option> : null}
            {cases.map((readiness) => (
              <option key={readiness.id} value={readiness.id}>
                {readiness.stable_identifier} · {readiness.status.toUpperCase()}
              </option>
            ))}
          </select>
        </label>
      </section>

      {busy ? (
        <p className="report-state" role="status">
          Reconciling current governed sources…
        </p>
      ) : null}

      {error === undefined ? null : (
        <div className="workspace-error report-error" role="alert">
          <span>{error}. No stale or partial report is shown.</span>
          <button className="button-secondary" type="button" onClick={retry}>
            Retry current report
          </button>
        </div>
      )}

      {!busy && error === undefined && cases.length === 0 ? (
        <p className="empty-state">Record a GO or HOLD decision to produce a report-grade view.</p>
      ) : null}

      {report === undefined ? null : <Report report={report} />}
    </section>
  );
}

function Report({ report }: { report: OperationalReport }) {
  const commercial = report.metrics.commercial;

  return (
    <div className="report-content">
      <section className="report-hero" aria-labelledby="report-outcome-title">
        <div>
          <span className={`report-outcome report-outcome--${report.outcome}`}>
            {report.outcome.replace("_", " ")}
          </span>
          <h2 id="report-outcome-title">{report.dimensions.sourcing_lane.name}</h2>
          <p>
            {report.dimensions.supplier.legal_name} · {report.dimensions.origin.name} to{" "}
            {report.dimensions.destination.name}
          </p>
        </div>
        <dl className="report-trust">
          <div>
            <dt>Freshness</dt>
            <dd>Live · {formatTimestamp(report.freshness.observed_at)}</dd>
          </div>
          <div>
            <dt>Reconciliation</dt>
            <dd>{report.reconciliation.status}</dd>
          </div>
          <div>
            <dt>Projection</dt>
            <dd title={report.projection_id}>{report.projection_id.slice(0, 12)}…</dd>
          </div>
        </dl>
      </section>

      <section className="report-metrics" aria-label="Approved commercial metrics">
        <Metric
          label="Quantity"
          value={`${formatDecimal(commercial.quantity)} ${commercial.unit_code}`}
        />
        <Metric
          label="Approved total"
          value={`${formatDecimal(commercial.approved_total)} ${commercial.currency_code}`}
        />
        <Metric label="Delivery" value={`${commercial.delivery_days} days`} />
        <Metric label="Required by" value={commercial.required_by} />
      </section>

      <section className="report-section" aria-labelledby="report-stages-title">
        <div className="report-section-heading">
          <div>
            <span className="eyebrow">Source-to-outcome lineage</span>
            <h2 id="report-stages-title">Six governed stages</h2>
          </div>
          <span>{report.metrics.lineage.audit_event_count} audit events</span>
        </div>
        <ol className="report-stages">
          {report.stages.map((stage) => (
            <li key={stage.code}>
              <span aria-hidden="true">✓</span>
              <div>
                <strong>{label(stage.code)}</strong>
                <small>
                  {stage.status} · version {stage.source_version}
                </small>
              </div>
            </li>
          ))}
        </ol>
      </section>

      <section className="report-section" aria-labelledby="report-evidence-title">
        <div className="report-section-heading">
          <div>
            <span className="eyebrow">Cryptographic evidence chain</span>
            <h2 id="report-evidence-title">Verified evidence</h2>
          </div>
          <span>{report.metrics.lineage.verified_evidence_count} objects</span>
        </div>
        <EvidenceTable evidence={report.evidence_lineage} />
      </section>

      <section className="report-section" aria-labelledby="report-audit-title">
        <div className="report-section-heading">
          <div>
            <span className="eyebrow">Attributable decisions</span>
            <h2 id="report-audit-title">Audit history</h2>
          </div>
          <span>{report.audit_events.length} bounded records</span>
        </div>
        <AuditTable events={report.audit_events} />
      </section>

      <section className="report-boundary" aria-labelledby="report-boundary-title">
        <div>
          <span className="eyebrow eyebrow--light">Authority boundary</span>
          <h2 id="report-boundary-title">Decision intelligence, never transaction authority.</h2>
        </div>
        <ul>
          <li>Source of truth: {yesNo(report.authority.source_of_truth)}</li>
          <li>
            Business mutation authorized: {yesNo(report.authority.business_mutation_authorized)}
          </li>
          <li>External effect created: {yesNo(report.authority.external_effect_created)}</li>
        </ul>
        <dl>
          {Object.entries(report.delivery_status_counts).map(([status, count]) => (
            <div key={status}>
              <dt>{label(status)}</dt>
              <dd>{count}</dd>
            </div>
          ))}
        </dl>
      </section>
    </div>
  );
}

function Metric({ label: metricLabel, value }: { label: string; value: string }) {
  return (
    <div>
      <span>{metricLabel}</span>
      <strong>{value}</strong>
    </div>
  );
}

function EvidenceTable({ evidence }: { evidence: ReportEvidence[] }) {
  return (
    <div className="report-table-scroll" tabIndex={0} aria-label="Scrollable evidence table">
      <table>
        <thead>
          <tr>
            <th scope="col">Stage</th>
            <th scope="col">Classification</th>
            <th scope="col">State</th>
            <th scope="col">Digest</th>
          </tr>
        </thead>
        <tbody>
          {evidence.map((item) => (
            <tr key={item.evidence_id}>
              <th scope="row">{label(item.stage)}</th>
              <td>{item.classification}</td>
              <td>{item.state}</td>
              <td title={item.sha256}>{item.sha256.slice(0, 14)}…</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function AuditTable({ events }: { events: ReportAuditEvent[] }) {
  return (
    <div className="report-table-scroll" tabIndex={0} aria-label="Scrollable audit table">
      <table>
        <thead>
          <tr>
            <th scope="col">Time</th>
            <th scope="col">Action</th>
            <th scope="col">Record</th>
            <th scope="col">Outcome</th>
            <th scope="col">Reason</th>
          </tr>
        </thead>
        <tbody>
          {events.map((event) => (
            <tr key={event.id}>
              <td>{formatTimestamp(event.occurred_at)}</td>
              <th scope="row">{label(event.action)}</th>
              <td>{label(event.resource_type)}</td>
              <td>{event.outcome}</td>
              <td>{event.reason}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function label(value: string) {
  return value.replaceAll("_", " ").replace(/\b\w/g, (character) => character.toUpperCase());
}

function formatTimestamp(value: string) {
  const parsed = new Date(value);
  return Number.isNaN(parsed.valueOf()) ? value : parsed.toLocaleString();
}

function formatDecimal(value: string) {
  return value.includes(".") ? value.replace(/(\.\d*?[1-9])0+$|\.0+$/, "$1") : value;
}

function yesNo(value: boolean) {
  return value ? "Yes" : "No";
}

function message(reason: unknown) {
  return reason instanceof Error ? reason.message : "The report was rejected";
}
