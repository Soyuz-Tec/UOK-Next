import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";

import {
  listParties,
  listReviewTasks,
  type Party,
  type ReviewTask,
} from "../master-parties/partyApi";
import { listSourcingLanes, type SourcingLane } from "./sourcingApi";
import {
  createComparison,
  createQuote,
  createRequisition,
  createRfq,
  decideComparison,
  listComparisons,
  listQuotes,
  listRequisitions,
  listRfqs,
  uploadQuoteEvidence,
  type QuoteComparison,
  type Requisition,
  type Rfq,
  type SupplierQuote,
} from "./procurementApi";
import { ProcurementCommandGrid } from "./ProcurementCommandGrid";
import { ComparisonTable } from "./ProcurementResults";

type Props = { token: string; tenantId: string; onSignOut: () => void };
type Data = [
  SourcingLane[],
  Party[],
  Requisition[],
  Rfq[],
  SupplierQuote[],
  QuoteComparison[],
  ReviewTask[],
];

export function ProcurementWorkspace({ token, tenantId, onSignOut }: Props) {
  const [lanes, setLanes] = useState<SourcingLane[]>([]);
  const [parties, setParties] = useState<Party[]>([]);
  const [requisitions, setRequisitions] = useState<Requisition[]>([]);
  const [rfqs, setRfqs] = useState<Rfq[]>([]);
  const [quotes, setQuotes] = useState<SupplierQuote[]>([]);
  const [comparisons, setComparisons] = useState<QuoteComparison[]>([]);
  const [tasks, setTasks] = useState<ReviewTask[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [selectedLane, setSelectedLane] = useState("");
  const [selectedRequisition, setSelectedRequisition] = useState("");
  const [selectedRfq, setSelectedRfq] = useState("");
  const [supplierIds, setSupplierIds] = useState<string[]>([]);
  const [quoteSupplier, setQuoteSupplier] = useState("");
  const [quantity, setQuantity] = useState("25");
  const [unitCode, setUnitCode] = useState("MT");
  const [unitPrice, setUnitPrice] = useState("100");
  const [deliveryDays, setDeliveryDays] = useState(14);

  const applyData = useCallback((data: Data) => {
    setLanes(data[0].filter((lane) => lane.status === "approved"));
    setParties(data[1].filter((party) => party.status === "approved"));
    setRequisitions(data[2]);
    setRfqs(data[3]);
    setQuotes(data[4]);
    setComparisons(data[5]);
    setTasks(data[6]);
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

  const activeRfq = useMemo(() => rfqs.find((rfq) => rfq.id === selectedRfq), [rfqs, selectedRfq]);
  const invitationIds = activeRfq?.supplier_party_ids ?? [];

  async function command(operation: () => Promise<unknown>) {
    setBusy(true);
    setError(undefined);
    try {
      await operation();
      await refresh();
    } catch (reason) {
      setError(message(reason));
    } finally {
      setBusy(false);
    }
  }

  function submitRequisition(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (selectedLane === "") return;
    void command(() =>
      createRequisition(token, {
        stable_identifier: `requisition-${crypto.randomUUID()}`,
        sourcing_lane_id: selectedLane,
        quantity,
        unit_code: unitCode,
        required_by: futureDate(30),
        reason: "Create a governed purchasing requirement",
      }),
    );
  }

  function submitRfq(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const requisition = requisitions.find((item) => item.id === selectedRequisition);
    if (requisition === undefined || supplierIds.length < 2) return;
    void command(() => createRfq(token, requisition, supplierIds, "USD", futureDateTime(7)));
  }

  function submitQuote(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (activeRfq === undefined || quoteSupplier === "") return;
    void command(() =>
      createQuote(token, activeRfq, quoteSupplier, quantity, unitPrice, deliveryDays),
    );
  }

  function selectRfq(rfqId: string) {
    setSelectedRfq(rfqId);
    setQuoteSupplier("");
    const rfq = rfqs.find((item) => item.id === rfqId);
    const requisition = requisitions.find((item) => item.id === rfq?.requisition_id);
    if (requisition !== undefined) setQuantity(requisition.quantity);
  }

  return (
    <section
      className="sourcing-workspace procurement-workspace"
      id="rfq-comparison"
      aria-labelledby="procurement-title"
    >
      <header className="workspace-heading">
        <div>
          <span className="eyebrow">Gate 3 · governed procurement round</span>
          <h1 id="procurement-title">Compare attributable offers, not opaque scores.</h1>
          <p>Tenant {tenantId.slice(0, 8)}… · server-owned ranking and exact human approval.</p>
        </div>
        <button className="button-secondary" type="button" onClick={onSignOut}>
          Sign out
        </button>
      </header>

      <div className="workflow-steps" aria-label="Procurement stages">
        {[
          ["01", "Requirement", "Approved sourcing lane"],
          ["02", "RFQ", "Approved invited suppliers"],
          ["03", "Quotes", "Verified attributable evidence"],
          ["04", "Comparison", "Deterministic human decision"],
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

      <ProcurementCommandGrid
        lanes={lanes}
        parties={parties}
        requisitions={requisitions}
        rfqs={rfqs}
        quotes={quotes}
        selectedLane={selectedLane}
        selectedRequisition={selectedRequisition}
        selectedRfq={selectedRfq}
        supplierIds={supplierIds}
        quoteSupplier={quoteSupplier}
        invitationIds={invitationIds}
        quantity={quantity}
        unitCode={unitCode}
        unitPrice={unitPrice}
        deliveryDays={deliveryDays}
        busy={busy}
        onLane={setSelectedLane}
        onRequisition={setSelectedRequisition}
        onRfq={selectRfq}
        onSuppliers={setSupplierIds}
        onQuoteSupplier={setQuoteSupplier}
        onQuantity={setQuantity}
        onUnitCode={setUnitCode}
        onUnitPrice={setUnitPrice}
        onDeliveryDays={setDeliveryDays}
        onSubmitRequisition={submitRequisition}
        onSubmitRfq={submitRfq}
        onSubmitQuote={submitQuote}
        onEvidence={(quote, file) => command(() => uploadQuoteEvidence(token, quote, file))}
        onCompare={(rfq) => command(() => createComparison(token, rfq))}
      />

      <ComparisonTable
        comparisons={comparisons}
        tasks={tasks}
        parties={parties}
        busy={busy}
        onDecision={(comparison, task, decision) =>
          command(() => decideComparison(token, comparison, task, decision))
        }
      />
    </section>
  );
}

function load(token: string): Promise<Data> {
  return Promise.all([
    listSourcingLanes(token),
    listParties(token),
    listRequisitions(token),
    listRfqs(token),
    listQuotes(token),
    listComparisons(token),
    listReviewTasks(token),
  ]);
}
function futureDate(days: number) {
  const date = new Date(Date.now() + days * 86_400_000);
  return date.toISOString().slice(0, 10);
}
function futureDateTime(days: number) {
  return new Date(Date.now() + days * 86_400_000).toISOString();
}
function message(reason: unknown) {
  return reason instanceof Error ? reason.message : "The command was rejected";
}
