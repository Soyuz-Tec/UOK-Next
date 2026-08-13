import type { FormEventHandler } from "react";

import type { Party } from "../master-parties/partyApi";
import type { SourcingLane } from "./sourcingApi";
import type { Requisition, Rfq, SupplierQuote } from "./procurementApi";
import { QuoteRow } from "./ProcurementResults";

type Props = {
  lanes: SourcingLane[];
  parties: Party[];
  requisitions: Requisition[];
  rfqs: Rfq[];
  quotes: SupplierQuote[];
  selectedLane: string;
  selectedRequisition: string;
  selectedRfq: string;
  supplierIds: string[];
  quoteSupplier: string;
  invitationIds: string[];
  quantity: string;
  unitCode: string;
  unitPrice: string;
  deliveryDays: number;
  busy: boolean;
  onLane: (value: string) => void;
  onRequisition: (value: string) => void;
  onRfq: (value: string) => void;
  onSuppliers: (value: string[]) => void;
  onQuoteSupplier: (value: string) => void;
  onQuantity: (value: string) => void;
  onUnitCode: (value: string) => void;
  onUnitPrice: (value: string) => void;
  onDeliveryDays: (value: number) => void;
  onSubmitRequisition: FormEventHandler<HTMLFormElement>;
  onSubmitRfq: FormEventHandler<HTMLFormElement>;
  onSubmitQuote: FormEventHandler<HTMLFormElement>;
  onEvidence: (quote: SupplierQuote, file: File) => Promise<unknown>;
  onCompare: (rfq: Rfq) => Promise<unknown>;
};

export function ProcurementCommandGrid(props: Props) {
  const readyRequisitions = props.requisitions.filter((item) => item.status === "ready_for_rfq");
  const openRfqs = props.rfqs.filter((rfq) => rfq.status === "open");

  return (
    <div className="procurement-grid">
      <form className="work-panel compact-command" onSubmit={props.onSubmitRequisition}>
        <span className="eyebrow">1 · Requirement</span>
        <h2>Purchase requisition</h2>
        <label>
          Approved sourcing lane
          <select
            value={props.selectedLane}
            onChange={(event) => props.onLane(event.target.value)}
            required
          >
            <option value="">Choose a lane</option>
            {props.lanes.map((lane) => (
              <option key={lane.id} value={lane.id}>
                {lane.name}
              </option>
            ))}
          </select>
        </label>
        <label>
          Quantity
          <input
            value={props.quantity}
            onChange={(event) => props.onQuantity(event.target.value)}
            inputMode="decimal"
            required
          />
        </label>
        <label>
          Unit code
          <input
            value={props.unitCode}
            onChange={(event) => props.onUnitCode(event.target.value.toUpperCase())}
            maxLength={16}
            required
          />
        </label>
        <button className="button-primary" disabled={props.busy || props.selectedLane === ""}>
          Create requisition
        </button>
      </form>

      <form className="work-panel compact-command" onSubmit={props.onSubmitRfq}>
        <span className="eyebrow">2 · Invitation</span>
        <h2>Open RFQ</h2>
        <label>
          Ready requisition
          <select
            value={props.selectedRequisition}
            onChange={(event) => props.onRequisition(event.target.value)}
            required
          >
            <option value="">Choose a requirement</option>
            {readyRequisitions.map((item) => (
              <option key={item.id} value={item.id}>
                {item.stable_identifier}
              </option>
            ))}
          </select>
        </label>
        <label>
          Approved suppliers
          <select
            multiple
            value={props.supplierIds}
            onChange={(event) =>
              props.onSuppliers(Array.from(event.target.selectedOptions, (option) => option.value))
            }
            required
          >
            {props.parties.map((party) => (
              <option key={party.id} value={party.id}>
                {party.legal_name}
              </option>
            ))}
          </select>
          <small>Select at least two suppliers.</small>
        </label>
        <button className="button-primary" disabled={props.busy || props.supplierIds.length < 2}>
          Open RFQ
        </button>
      </form>

      <form className="work-panel compact-command" onSubmit={props.onSubmitQuote}>
        <span className="eyebrow">3 · Attributable offer</span>
        <h2>Record quote</h2>
        <label>
          Open RFQ
          <select
            value={props.selectedRfq}
            onChange={(event) => props.onRfq(event.target.value)}
            required
          >
            <option value="">Choose an RFQ</option>
            {openRfqs.map((rfq) => (
              <option key={rfq.id} value={rfq.id}>
                {rfq.stable_identifier}
              </option>
            ))}
          </select>
        </label>
        <label>
          Invited supplier
          <select
            value={props.quoteSupplier}
            onChange={(event) => props.onQuoteSupplier(event.target.value)}
            required
          >
            <option value="">Choose a supplier</option>
            {props.parties
              .filter((party) => props.invitationIds.includes(party.id))
              .map((party) => (
                <option key={party.id} value={party.id}>
                  {party.legal_name}
                </option>
              ))}
          </select>
        </label>
        <label>
          Unit price
          <input
            value={props.unitPrice}
            onChange={(event) => props.onUnitPrice(event.target.value)}
            inputMode="decimal"
            required
          />
        </label>
        <label>
          Delivery days
          <input
            type="number"
            min="0"
            max="3650"
            value={props.deliveryDays}
            onChange={(event) => props.onDeliveryDays(Number(event.target.value))}
            required
          />
        </label>
        <button className="button-primary" disabled={props.busy || props.quoteSupplier === ""}>
          Create draft quote
        </button>
      </form>

      <div className="work-panel compact-command">
        <span className="eyebrow">4 · Evidence and comparison</span>
        <h2>Close with evidence</h2>
        {props.quotes.length === 0 ? (
          <p className="empty-state">No quote drafts yet.</p>
        ) : (
          props.quotes.map((quote) => (
            <QuoteRow
              key={quote.id}
              quote={quote}
              party={props.parties.find((party) => party.id === quote.supplier_party_id)}
              busy={props.busy}
              onEvidence={(file) => props.onEvidence(quote, file)}
            />
          ))
        )}
        {openRfqs.map((rfq) => (
          <button
            key={rfq.id}
            className="button-secondary"
            type="button"
            disabled={
              props.busy ||
              props.quotes.filter(
                (quote) => quote.rfq_id === rfq.id && quote.status === "submitted",
              ).length < 2
            }
            onClick={() => void props.onCompare(rfq)}
          >
            Compare {rfq.stable_identifier}
          </button>
        ))}
      </div>
    </div>
  );
}
