import type { Party, ReviewTask } from "../master-parties/partyApi";
import type { QuoteComparison, SupplierQuote } from "./procurementApi";

export function QuoteRow({
  quote,
  party,
  busy,
  onEvidence,
}: {
  quote: SupplierQuote;
  party: Party | undefined;
  busy: boolean;
  onEvidence: (file: File) => Promise<unknown>;
}) {
  return (
    <div className="quote-row">
      <span>
        <strong>{party?.legal_name ?? quote.supplier_party_id.slice(0, 8)}</strong>
        <small>
          {quote.unit_price} {quote.currency_code} · {quote.delivery_days} days
        </small>
      </span>
      <span className={`status status--${quote.status}`}>{quote.status}</span>
      {quote.status === "draft" ? (
        <label className="file-action">
          Attach evidence
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
    </div>
  );
}

export function ComparisonTable({
  comparisons,
  tasks,
  parties,
  busy,
  onDecision,
}: {
  comparisons: QuoteComparison[];
  tasks: ReviewTask[];
  parties: Party[];
  busy: boolean;
  onDecision: (
    comparison: QuoteComparison,
    task: ReviewTask,
    decision: "approve" | "hold",
  ) => Promise<unknown>;
}) {
  return (
    <section className="comparison-panel" aria-labelledby="comparison-results">
      <span className="eyebrow">Decision evidence</span>
      <h2 id="comparison-results">Deterministic comparison snapshots</h2>
      {comparisons.length === 0 ? (
        <p className="empty-state">Two submitted quotes are required.</p>
      ) : (
        comparisons.map((comparison) => (
          <ComparisonCard
            key={comparison.id}
            comparison={comparison}
            task={tasks.find((item) => item.subject_id === comparison.id)}
            parties={parties}
            busy={busy}
            onDecision={onDecision}
          />
        ))
      )}
    </section>
  );
}

function ComparisonCard({
  comparison,
  task,
  parties,
  busy,
  onDecision,
}: {
  comparison: QuoteComparison;
  task: ReviewTask | undefined;
  parties: Party[];
  busy: boolean;
  onDecision: (
    comparison: QuoteComparison,
    task: ReviewTask,
    decision: "approve" | "hold",
  ) => Promise<unknown>;
}) {
  return (
    <article className="comparison-card">
      <header>
        <strong>{comparison.stable_identifier}</strong>
        <span className={`status status--${comparison.status}`}>{comparison.status}</span>
      </header>
      <div className="ranking-table">
        {comparison.ranking_snapshot.ranking.map((row, index) => (
          <div
            key={row.quote_id}
            className={
              row.quote_id === comparison.recommended_quote_id
                ? "ranking-row ranking-row--recommended"
                : "ranking-row"
            }
          >
            <span>#{index + 1}</span>
            <strong>
              {parties.find((party) => party.id === row.supplier_party_id)?.legal_name ??
                row.supplier_party_id.slice(0, 8)}
            </strong>
            <span>
              {row.total_price} {row.currency_code}
            </span>
            <span>{row.delivery_days} days</span>
          </div>
        ))}
      </div>
      {task === undefined ? null : (
        <footer>
          <button
            className="button-secondary"
            disabled={busy}
            onClick={() => void onDecision(comparison, task, "hold")}
          >
            Hold
          </button>
          <button
            className="button-primary"
            disabled={busy}
            onClick={() => void onDecision(comparison, task, "approve")}
          >
            Approve comparison
          </button>
        </footer>
      )}
    </article>
  );
}
