import { authorizedRequest } from "../../shared/authorizedApi";
import type { ReviewTask } from "../master-parties/partyApi";

export type Requisition = {
  id: string;
  stable_identifier: string;
  sourcing_lane_id: string;
  quantity: string;
  unit_code: string;
  required_by: string;
  status: "ready_for_rfq" | "rfq_open";
  lock_version: number;
};

export type Rfq = {
  id: string;
  stable_identifier: string;
  requisition_id: string;
  settlement_currency_code: string;
  response_deadline: string;
  supplier_party_ids: string[];
  status: "open" | "comparison_pending" | "compared" | "hold";
  lock_version: number;
};

export type SupplierQuote = {
  id: string;
  stable_identifier: string;
  rfq_id: string;
  supplier_party_id: string;
  quoted_quantity: string;
  unit_price: string;
  currency_code: string;
  delivery_days: number;
  status: "draft" | "submitted";
  lock_version: number;
};

export type RankingRow = {
  quote_id: string;
  supplier_party_id: string;
  quote_version: number;
  quoted_quantity: string;
  unit_price: string;
  total_price: string;
  currency_code: string;
  delivery_days: number;
};

export type QuoteComparison = {
  id: string;
  stable_identifier: string;
  rfq_id: string;
  recommended_quote_id: string;
  ranking_snapshot: { formula_version: number; ranking: RankingRow[] };
  status: "awaiting_review" | "approved" | "hold";
  lock_version: number;
  review_task?: ReviewTask;
};

const commandHeaders = () => ({
  "content-type": "application/json",
  "idempotency-key": crypto.randomUUID(),
});

export const listRequisitions = (token: string) =>
  authorizedRequest<Requisition[]>("/api/v1/purchase-requisitions?limit=100", token);

export const listRfqs = (token: string) =>
  authorizedRequest<Rfq[]>("/api/v1/rfqs?limit=100", token);

export const listQuotes = (token: string) =>
  authorizedRequest<SupplierQuote[]>("/api/v1/supplier-quotes?limit=100", token);

export const listComparisons = (token: string) =>
  authorizedRequest<QuoteComparison[]>("/api/v1/quote-comparisons?limit=100", token);

export function createRequisition(
  token: string,
  input: {
    stable_identifier: string;
    sourcing_lane_id: string;
    quantity: string;
    unit_code: string;
    required_by: string;
    reason: string;
  },
) {
  return authorizedRequest<Requisition>("/api/v1/purchase-requisitions", token, {
    method: "POST",
    headers: commandHeaders(),
    body: JSON.stringify(input),
  });
}

export function createRfq(
  token: string,
  requisition: Requisition,
  supplierPartyIds: string[],
  currency: string,
  deadline: string,
) {
  return authorizedRequest<Rfq>("/api/v1/rfqs", token, {
    method: "POST",
    headers: commandHeaders(),
    body: JSON.stringify({
      stable_identifier: `rfq-${crypto.randomUUID()}`,
      requisition_id: requisition.id,
      expected_version: requisition.lock_version,
      settlement_currency_code: currency,
      response_deadline: deadline,
      supplier_party_ids: supplierPartyIds,
      reason: "Invite approved suppliers to provide attributable quotes",
    }),
  });
}

export function createQuote(
  token: string,
  rfq: Rfq,
  supplierPartyId: string,
  quantity: string,
  unitPrice: string,
  deliveryDays: number,
) {
  return authorizedRequest<SupplierQuote>("/api/v1/supplier-quotes", token, {
    method: "POST",
    headers: commandHeaders(),
    body: JSON.stringify({
      stable_identifier: `quote-${crypto.randomUUID()}`,
      rfq_id: rfq.id,
      supplier_party_id: supplierPartyId,
      quoted_quantity: quantity,
      unit_price: unitPrice,
      currency_code: rfq.settlement_currency_code,
      delivery_days: deliveryDays,
      reason: "Record an attributable supplier quote",
    }),
  });
}

export function uploadQuoteEvidence(token: string, quote: SupplierQuote, file: File) {
  const body = new FormData();
  body.set("evidence_id", crypto.randomUUID());
  body.set("expected_version", String(quote.lock_version));
  body.set("classification", "confidential");
  body.set("reason", "Attach attributable supplier quote evidence");
  body.set("file", file);
  return authorizedRequest<SupplierQuote>(`/api/v1/supplier-quotes/${quote.id}/evidence`, token, {
    method: "POST",
    headers: { "idempotency-key": crypto.randomUUID() },
    body,
  });
}

export function createComparison(token: string, rfq: Rfq) {
  return authorizedRequest<QuoteComparison>("/api/v1/quote-comparisons", token, {
    method: "POST",
    headers: commandHeaders(),
    body: JSON.stringify({
      stable_identifier: `comparison-${crypto.randomUUID()}`,
      rfq_id: rfq.id,
      expected_version: rfq.lock_version,
      reason: "Create a deterministic attributable quote comparison",
    }),
  });
}

export function decideComparison(
  token: string,
  comparison: QuoteComparison,
  task: ReviewTask,
  decision: "approve" | "hold",
) {
  return authorizedRequest<QuoteComparison>(
    `/api/v1/quote-comparisons/${comparison.id}/decision`,
    token,
    {
      method: "POST",
      headers: commandHeaders(),
      body: JSON.stringify({
        decision,
        reason: `Record human ${decision} decision for the attributable comparison`,
        task_id: task.id,
        expected_version: comparison.lock_version,
      }),
    },
  );
}
