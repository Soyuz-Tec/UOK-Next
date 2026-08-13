import { useCallback, useEffect, useMemo, useState } from "react";

import {
  listParties,
  listReviewTasks,
  type Party,
  type ReviewTask,
} from "../master-parties/partyApi";
import { listComparisons, type QuoteComparison } from "../trade-sourcing/procurementApi";
import {
  createPurchaseCommitmentProposal,
  decidePurchaseCommitmentProposal,
  listPurchaseCommitmentProposals,
  uploadPurchaseCommitmentEvidence,
  type PurchaseCommitmentProposal,
} from "./commitmentApi";

type Props = { token: string; tenantId: string; onSignOut: () => void };
type Data = [QuoteComparison[], PurchaseCommitmentProposal[], ReviewTask[], Party[]];

export function PurchaseCommitmentWorkspace({ token, tenantId, onSignOut }: Props) {
  const [comparisons, setComparisons] = useState<QuoteComparison[]>([]);
  const [proposals, setProposals] = useState<PurchaseCommitmentProposal[]>([]);
  const [tasks, setTasks] = useState<ReviewTask[]>([]);
  const [parties, setParties] = useState<Party[]>([]);
  const [selectedComparison, setSelectedComparison] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  const applyData = useCallback((data: Data) => {
    setComparisons(data[0].filter((comparison) => comparison.status === "approved"));
    setProposals(data[1]);
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
      comparisons.filter(
        (comparison) =>
          proposals.find((proposal) => proposal.quote_comparison_id === comparison.id) ===
          undefined,
      ),
    [comparisons, proposals],
  );

  const effectiveSelection = selectedComparison || available[0]?.id || "";

  async function command(operation: () => Promise<unknown>) {
    setBusy(true);
    setError(undefined);
    try {
      await operation();
      setSelectedComparison("");
      await refresh();
    } catch (reason) {
      setError(message(reason));
    } finally {
      setBusy(false);
    }
  }

  function createProposal() {
    const comparison = comparisons.find((item) => item.id === effectiveSelection);
    if (comparison !== undefined) {
      void command(() => createPurchaseCommitmentProposal(token, comparison));
    }
  }

  return (
    <section
      className="commitment-workspace"
      id="commitment-proposal"
      aria-labelledby="commitment-title"
    >
      <header className="workspace-heading">
        <div>
          <span className="eyebrow">Gate 3 · controlled commitment handoff</span>
          <h1 id="commitment-title">Propose once from approved source terms.</h1>
          <p>Tenant {tenantId.slice(0, 8)}… · no re-keying, no contract, no external effect.</p>
        </div>
        <button className="button-secondary" type="button" onClick={onSignOut}>
          Sign out
        </button>
      </header>

      <div className="workflow-steps" aria-label="Commitment proposal stages">
        {[
          ["01", "Source", "Exact approved comparison"],
          ["02", "Evidence", "Verified internal rationale"],
          ["03", "Decision", "Exact approve or HOLD"],
          ["04", "Boundary", "No downstream side effect"],
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

      <section className="commitment-create" aria-labelledby="proposal-source-title">
        <div>
          <span className="eyebrow">Fast source handoff</span>
          <h2 id="proposal-source-title">Approved comparison</h2>
          <p>The server copies and revalidates every material term. Only the source is selected.</p>
        </div>
        <label>
          Available comparison
          <select
            value={effectiveSelection}
            onChange={(event) => setSelectedComparison(event.target.value)}
          >
            <option value="">Choose an approved comparison</option>
            {available.map((comparison) => (
              <option key={comparison.id} value={comparison.id}>
                {comparison.stable_identifier}
              </option>
            ))}
          </select>
        </label>
        <button
          className="button-primary"
          type="button"
          disabled={busy || effectiveSelection === ""}
          onClick={createProposal}
        >
          Create source-bound proposal
        </button>
      </section>

      <section className="proposal-list" aria-labelledby="proposal-list-title">
        <div>
          <span className="eyebrow">Decision workbench</span>
          <h2 id="proposal-list-title">Purchase-commitment proposals</h2>
        </div>
        {proposals.length === 0 ? (
          <p className="empty-state">No proposal has been created from an approved comparison.</p>
        ) : (
          proposals.map((proposal) => (
            <ProposalCard
              key={proposal.id}
              proposal={proposal}
              party={parties.find(
                (candidate) => candidate.id === proposal.source_snapshot.supplier_party_id,
              )}
              task={tasks.find((task) => task.subject_id === proposal.id)}
              busy={busy}
              onEvidence={(file) =>
                command(() => uploadPurchaseCommitmentEvidence(token, proposal, file))
              }
              onDecision={(task, decision) =>
                command(() => decidePurchaseCommitmentProposal(token, proposal, task, decision))
              }
            />
          ))
        )}
      </section>
    </section>
  );
}

function ProposalCard({
  proposal,
  party,
  task,
  busy,
  onEvidence,
  onDecision,
}: {
  proposal: PurchaseCommitmentProposal;
  party: Party | undefined;
  task: ReviewTask | undefined;
  busy: boolean;
  onEvidence: (file: File) => Promise<unknown>;
  onDecision: (task: ReviewTask, decision: "approve" | "hold") => Promise<unknown>;
}) {
  const source = proposal.source_snapshot;

  return (
    <article className="proposal-card">
      <header>
        <div>
          <strong>{proposal.stable_identifier}</strong>
          <small>Comparison {source.quote_comparison_id.slice(0, 8)}…</small>
        </div>
        <span className={`status status--${proposal.status}`}>{proposal.status}</span>
      </header>
      <dl className="proposal-terms">
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
          <dt>Unit price</dt>
          <dd>
            {source.unit_price} {source.currency_code}
          </dd>
        </div>
        <div>
          <dt>Total</dt>
          <dd>
            {source.total_price} {source.currency_code}
          </dd>
        </div>
        <div>
          <dt>Delivery</dt>
          <dd>{source.delivery_days} days</dd>
        </div>
        <div>
          <dt>Required by</dt>
          <dd>{source.required_by}</dd>
        </div>
      </dl>
      <div className="source-lineage">
        <span>Formula v{source.formula_version}</span>
        <span>Quote v{source.selected_quote_version}</span>
        <span>Evidence {source.quote_evidence.sha256.slice(0, 10)}…</span>
      </div>
      {proposal.status === "draft" ? (
        <label className="proposal-evidence-action">
          Attach internal proposal evidence
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
            Hold
          </button>
          <button
            className="button-primary"
            disabled={busy}
            onClick={() => void onDecision(task, "approve")}
          >
            Approve proposal
          </button>
        </footer>
      )}
      {proposal.status === "approved" ? (
        <p className="boundary-confirmation">
          Approved internally · commitment and external effect remain false.
        </p>
      ) : null}
    </article>
  );
}

function load(token: string): Promise<Data> {
  return Promise.all([
    listComparisons(token),
    listPurchaseCommitmentProposals(token),
    listReviewTasks(token),
    listParties(token),
  ]);
}

function message(reason: unknown) {
  return reason instanceof Error ? reason.message : "The command was rejected";
}
