import { useCallback, useEffect, useMemo, useState } from "react";

import {
  listParties,
  listReviewTasks,
  type Party,
  type ReviewTask,
} from "../master-parties/partyApi";
import {
  listPurchaseCommitmentProposals,
  type PurchaseCommitmentProposal,
} from "../trade-contracts/commitmentApi";
import {
  createShipmentReadinessCase,
  decideShipmentReadiness,
  listShipmentReadinessCases,
  uploadShipmentReadinessEvidence,
  type ReadinessCheck,
  type ShipmentReadinessCase,
} from "./readinessApi";

type Props = { token: string; tenantId: string; onSignOut: () => void };
type Data = [PurchaseCommitmentProposal[], ShipmentReadinessCase[], ReviewTask[], Party[]];

const checkLabels: Record<string, string> = {
  approved_proposal: "Approved proposal",
  current_commercial_source: "Current commercial source",
  verified_commercial_evidence: "Commercial evidence",
  verified_operational_readiness_evidence: "Operational readiness evidence",
};

export function ShipmentReadinessWorkspace({ token, tenantId, onSignOut }: Props) {
  const [proposals, setProposals] = useState<PurchaseCommitmentProposal[]>([]);
  const [readinessCases, setReadinessCases] = useState<ShipmentReadinessCase[]>([]);
  const [tasks, setTasks] = useState<ReviewTask[]>([]);
  const [parties, setParties] = useState<Party[]>([]);
  const [selectedProposal, setSelectedProposal] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  const applyData = useCallback((data: Data) => {
    setProposals(data[0].filter((proposal) => proposal.status === "approved"));
    setReadinessCases(data[1]);
    setTasks(data[2]);
    setParties(data[3]);
  }, []);

  const refresh = useCallback(async () => applyData(await load(token)), [applyData, token]);

  useEffect(() => {
    let active = true;
    void load(token)
      .then((data) => active && applyData(data))
      .catch((reason: unknown) => active && setError(message(reason)));
    return () => {
      active = false;
    };
  }, [applyData, token]);

  const available = useMemo(
    () =>
      proposals.filter(
        (proposal) =>
          readinessCases.find(
            (readiness) => readiness.purchase_commitment_proposal_id === proposal.id,
          ) === undefined,
      ),
    [proposals, readinessCases],
  );

  const effectiveSelection = selectedProposal || available[0]?.id || "";

  async function command(operation: () => Promise<unknown>) {
    setBusy(true);
    setError(undefined);
    try {
      await operation();
      setSelectedProposal("");
      await refresh();
    } catch (reason) {
      setError(message(reason));
    } finally {
      setBusy(false);
    }
  }

  function createReadiness() {
    const proposal = proposals.find((item) => item.id === effectiveSelection);
    if (proposal !== undefined) void command(() => createShipmentReadinessCase(token, proposal));
  }

  return (
    <section
      className="readiness-workspace"
      id="shipment-readiness"
      aria-labelledby="readiness-title"
    >
      <header className="workspace-heading">
        <div>
          <span className="eyebrow">Gate 3 · evidence-first execution control</span>
          <h1 id="readiness-title">Decide readiness without releasing execution.</h1>
          <p>
            Tenant {tenantId.slice(0, 8)}… · three actions, zero term re-entry, zero side effects.
          </p>
        </div>
        <button className="button-secondary" type="button" onClick={onSignOut}>
          Sign out
        </button>
      </header>

      <div className="workflow-steps" aria-label="Shipment-readiness stages">
        {[
          ["01", "Source", "Exact approved proposal"],
          ["02", "Evidence", "One governed readiness bundle"],
          ["03", "Decision", "Exact GO or HOLD"],
          ["04", "Boundary", "No release or downstream effect"],
        ].map(([number, title, detail]) => (
          <div key={number}>
            <span>{number}</span>
            <strong>{title}</strong>
            <small>{detail}</small>
          </div>
        ))}
      </div>

      {error === undefined ? null : (
        <div className="workspace-error" role="alert">
          {error}
        </div>
      )}

      <section className="readiness-create" aria-labelledby="readiness-source-title">
        <div>
          <span className="eyebrow">One-step source handoff</span>
          <h2 id="readiness-source-title">Approved commitment proposal</h2>
          <p>Every term, source version, and commercial evidence reference is server-derived.</p>
        </div>
        <label>
          Available proposal
          <select
            value={effectiveSelection}
            onChange={(event) => setSelectedProposal(event.target.value)}
          >
            <option value="">Choose an approved proposal</option>
            {available.map((proposal) => (
              <option key={proposal.id} value={proposal.id}>
                {proposal.stable_identifier}
              </option>
            ))}
          </select>
        </label>
        <button
          className="button-primary"
          type="button"
          disabled={busy || effectiveSelection === ""}
          onClick={createReadiness}
        >
          Open readiness gate
        </button>
      </section>

      <section className="readiness-list" aria-labelledby="readiness-list-title">
        <div>
          <span className="eyebrow">Decision workbench</span>
          <h2 id="readiness-list-title">Shipment-readiness cases</h2>
        </div>
        {readinessCases.length === 0 ? (
          <p className="empty-state">
            No readiness gate has been opened from an approved proposal.
          </p>
        ) : (
          readinessCases.map((readiness) => (
            <ReadinessCard
              key={readiness.id}
              readiness={readiness}
              party={parties.find(
                (candidate) =>
                  candidate.id === readiness.source_snapshot.commercial_source.supplier_party_id,
              )}
              task={tasks.find((task) => task.subject_id === readiness.id)}
              busy={busy}
              onEvidence={(file) =>
                command(() => uploadShipmentReadinessEvidence(token, readiness, file))
              }
              onDecision={(task, decision) =>
                command(() => decideShipmentReadiness(token, readiness, task, decision))
              }
            />
          ))
        )}
      </section>
    </section>
  );
}

function ReadinessCard({
  readiness,
  party,
  task,
  busy,
  onEvidence,
  onDecision,
}: {
  readiness: ShipmentReadinessCase;
  party: Party | undefined;
  task: ReviewTask | undefined;
  busy: boolean;
  onEvidence: (file: File) => Promise<unknown>;
  onDecision: (task: ReviewTask, decision: "go" | "hold") => Promise<unknown>;
}) {
  const source = readiness.source_snapshot.commercial_source;

  return (
    <article className="readiness-card-item">
      <header>
        <div>
          <strong>{readiness.stable_identifier}</strong>
          <small>Proposal {readiness.purchase_commitment_proposal_id.slice(0, 8)}…</small>
        </div>
        <span className={`status status--${readiness.status}`}>{readiness.status}</span>
      </header>

      <dl className="readiness-terms">
        <div>
          <dt>Supplier</dt>
          <dd>{party?.legal_name ?? source.supplier_party_id.slice(0, 8)}</dd>
        </div>
        <div>
          <dt>Quantity</dt>
          <dd>
            {source.quantity} {source.unit_code}
          </dd>
        </div>
        <div>
          <dt>Approved total</dt>
          <dd>
            {source.total_price} {source.currency_code}
          </dd>
        </div>
        <div>
          <dt>Required by</dt>
          <dd>{source.required_by}</dd>
        </div>
      </dl>

      <div className="readiness-checks" aria-label="Server-owned readiness checklist">
        {readiness.checklist_snapshot.checks.map((check) => (
          <ReadinessSignal key={check.code} check={check} />
        ))}
      </div>

      <div className="source-lineage">
        <span>Readiness formula v{readiness.checklist_snapshot.formula_version}</span>
        <span>Proposal v{readiness.purchase_commitment_proposal_version}</span>
        <span>
          Commercial evidence {readiness.source_snapshot.proposal_evidence.sha256.slice(0, 10)}…
        </span>
      </div>

      {readiness.status === "draft" || readiness.status === "hold" ? (
        <label className="readiness-evidence-action">
          {readiness.status === "hold"
            ? "Attach corrected readiness evidence"
            : "Attach readiness evidence bundle"}
          <input
            type="file"
            disabled={busy}
            onChange={(event) => {
              const file = event.target.files?.[0];
              if (file !== undefined) void onEvidence(file);
            }}
          />
        </label>
      ) : null}

      {task === undefined ? null : (
        <footer>
          <button
            className="button-secondary"
            disabled={busy}
            onClick={() => void onDecision(task, "hold")}
          >
            HOLD
          </button>
          <button
            className="button-primary"
            disabled={busy}
            onClick={() => void onDecision(task, "go")}
          >
            Record GO
          </button>
        </footer>
      )}

      {readiness.status === "go" ? (
        <p className="boundary-confirmation">
          GO recorded · shipment, dispatch, inventory, finance, and external effects remain false.
        </p>
      ) : null}
    </article>
  );
}

function ReadinessSignal({ check }: { check: ReadinessCheck }) {
  return (
    <div className={`readiness-signal readiness-signal--${check.status}`}>
      <span aria-hidden="true">{check.status === "passed" ? "✓" : "·"}</span>
      <strong>{checkLabels[check.code] ?? check.code}</strong>
      <small>{check.status}</small>
    </div>
  );
}

function load(token: string): Promise<Data> {
  return Promise.all([
    listPurchaseCommitmentProposals(token),
    listShipmentReadinessCases(token),
    listReviewTasks(token),
    listParties(token),
  ]);
}

function message(reason: unknown) {
  return reason instanceof Error ? reason.message : "The command was rejected";
}
