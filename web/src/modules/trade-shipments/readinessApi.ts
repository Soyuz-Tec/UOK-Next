import { authorizedRequest } from "../../shared/authorizedApi";
import type { ReviewTask } from "../master-parties/partyApi";
import type {
  CommitmentSourceSnapshot,
  PurchaseCommitmentProposal,
} from "../trade-contracts/commitmentApi";

export type ReadinessCheck = {
  code: string;
  status: "pending" | "passed";
  authority: "server";
};

export type ShipmentReadinessCase = {
  id: string;
  stable_identifier: string;
  purchase_commitment_proposal_id: string;
  purchase_commitment_proposal_version: number;
  source_snapshot: {
    readiness_formula_version: 1;
    purchase_commitment_proposal_id: string;
    purchase_commitment_proposal_version: number;
    proposal_evidence: { evidence_id: string; sha256: string; classification: string };
    commercial_source: CommitmentSourceSnapshot;
  };
  checklist_snapshot: { formula_version: 1; checks: ReadinessCheck[] };
  status: "draft" | "awaiting_review" | "go" | "hold";
  evidence_metadata: { evidence_id: string; sha256: string; classification: string } | null;
  decision_reason: string | null;
  lock_version: number;
  shipment_created: false;
  dispatch_created: false;
  inventory_effect_created: false;
  finance_effect_created: false;
  external_effect_created: false;
  review_task?: ReviewTask;
};

const commandHeaders = () => ({
  "content-type": "application/json",
  "idempotency-key": crypto.randomUUID(),
});

export const listShipmentReadinessCases = (token: string) =>
  authorizedRequest<ShipmentReadinessCase[]>("/api/v1/shipment-readiness-cases?limit=100", token);

export function createShipmentReadinessCase(token: string, proposal: PurchaseCommitmentProposal) {
  return authorizedRequest<ShipmentReadinessCase>("/api/v1/shipment-readiness-cases", token, {
    method: "POST",
    headers: commandHeaders(),
    body: JSON.stringify({
      stable_identifier: `shipment-readiness-${crypto.randomUUID()}`,
      purchase_commitment_proposal_id: proposal.id,
      expected_proposal_version: proposal.lock_version,
      reason: "Create one source-bound non-executing shipment-readiness case",
    }),
  });
}

export function uploadShipmentReadinessEvidence(
  token: string,
  readiness: ShipmentReadinessCase,
  file: File,
) {
  const body = new FormData();
  body.set("evidence_id", crypto.randomUUID());
  body.set("expected_version", String(readiness.lock_version));
  body.set("classification", "confidential");
  body.set("reason", "Attach the reviewed operational-readiness evidence bundle");
  body.set("file", file);

  return authorizedRequest<ShipmentReadinessCase>(
    `/api/v1/shipment-readiness-cases/${readiness.id}/evidence`,
    token,
    { method: "POST", headers: { "idempotency-key": crypto.randomUUID() }, body },
  );
}

export function decideShipmentReadiness(
  token: string,
  readiness: ShipmentReadinessCase,
  task: ReviewTask,
  decision: "go" | "hold",
) {
  return authorizedRequest<ShipmentReadinessCase>(
    `/api/v1/shipment-readiness-cases/${readiness.id}/decision`,
    token,
    {
      method: "POST",
      headers: commandHeaders(),
      body: JSON.stringify({
        decision,
        reason: `Record exact human shipment-readiness ${decision.toUpperCase()}`,
        task_id: task.id,
        expected_version: readiness.lock_version,
      }),
    },
  );
}
