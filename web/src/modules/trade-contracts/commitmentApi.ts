import { authorizedRequest } from "../../shared/authorizedApi";
import type { ReviewTask } from "../master-parties/partyApi";
import type { QuoteComparison } from "../trade-sourcing/procurementApi";

export type CommitmentSourceSnapshot = {
  formula_version: number;
  quote_comparison_id: string;
  quote_comparison_version: number;
  rfq_id: string;
  rfq_version: number;
  requisition_id: string;
  requisition_version: number;
  sourcing_lane_id: string;
  sourcing_lane_version: number;
  selected_quote_id: string;
  selected_quote_version: number;
  supplier_party_id: string;
  quantity: string;
  unit_code: string;
  unit_price: string;
  total_price: string;
  currency_code: string;
  delivery_days: number;
  required_by: string;
  quote_evidence: { evidence_id: string; sha256: string; classification: string };
};

export type PurchaseCommitmentProposal = {
  id: string;
  stable_identifier: string;
  quote_comparison_id: string;
  quote_comparison_version: number;
  selected_quote_id: string;
  selected_quote_version: number;
  source_snapshot: CommitmentSourceSnapshot;
  status: "draft" | "awaiting_review" | "approved" | "hold";
  evidence_metadata: { evidence_id: string; sha256: string; classification: string } | null;
  decision_reason: string | null;
  lock_version: number;
  commitment_created: false;
  external_effect_created: false;
  review_task?: ReviewTask;
};

const commandHeaders = () => ({
  "content-type": "application/json",
  "idempotency-key": crypto.randomUUID(),
});

export const listPurchaseCommitmentProposals = (token: string) =>
  authorizedRequest<PurchaseCommitmentProposal[]>(
    "/api/v1/purchase-commitment-proposals?limit=100",
    token,
  );

export function createPurchaseCommitmentProposal(token: string, comparison: QuoteComparison) {
  return authorizedRequest<PurchaseCommitmentProposal>(
    "/api/v1/purchase-commitment-proposals",
    token,
    {
      method: "POST",
      headers: commandHeaders(),
      body: JSON.stringify({
        stable_identifier: `commitment-proposal-${crypto.randomUUID()}`,
        quote_comparison_id: comparison.id,
        expected_comparison_version: comparison.lock_version,
        reason: "Create one source-bound non-binding purchase commitment proposal",
      }),
    },
  );
}

export function uploadPurchaseCommitmentEvidence(
  token: string,
  proposal: PurchaseCommitmentProposal,
  file: File,
) {
  const body = new FormData();
  body.set("evidence_id", crypto.randomUUID());
  body.set("expected_version", String(proposal.lock_version));
  body.set("classification", "confidential");
  body.set("reason", "Attach the reviewed internal commitment rationale");
  body.set("file", file);

  return authorizedRequest<PurchaseCommitmentProposal>(
    `/api/v1/purchase-commitment-proposals/${proposal.id}/evidence`,
    token,
    { method: "POST", headers: { "idempotency-key": crypto.randomUUID() }, body },
  );
}

export function decidePurchaseCommitmentProposal(
  token: string,
  proposal: PurchaseCommitmentProposal,
  task: ReviewTask,
  decision: "approve" | "hold",
) {
  return authorizedRequest<PurchaseCommitmentProposal>(
    `/api/v1/purchase-commitment-proposals/${proposal.id}/decision`,
    token,
    {
      method: "POST",
      headers: commandHeaders(),
      body: JSON.stringify({
        decision,
        reason: `Record exact human ${decision} decision for the non-binding proposal`,
        task_id: task.id,
        expected_version: proposal.lock_version,
      }),
    },
  );
}
