import type { EvidenceObject, ReviewTask } from "../master-parties/partyApi";
import { authorizedRequest } from "../../shared/authorizedApi";

export type SourcingLane = {
  id: string;
  stable_identifier: string;
  name: string;
  supplier_party_id: string;
  product_id: string;
  origin_location_id: string;
  destination_location_id: string;
  status: "draft" | "evidence_submitted" | "approved" | "hold";
  lock_version: number;
  review_task?: ReviewTask;
  evidence_objects?: EvidenceObject[];
};

export type SourcingLaneInput = Omit<
  SourcingLane,
  "id" | "status" | "lock_version" | "review_task" | "evidence_objects"
> & { reason: string };

export const listSourcingLanes = (token: string) =>
  authorizedRequest<SourcingLane[]>("/api/v1/sourcing-lanes?limit=100", token);

export const createSourcingLane = (token: string, input: SourcingLaneInput) =>
  authorizedRequest<SourcingLane>("/api/v1/sourcing-lanes", token, {
    method: "POST",
    headers: { "content-type": "application/json", "idempotency-key": crypto.randomUUID() },
    body: JSON.stringify(input),
  });

export function uploadSourcingEvidence(
  token: string,
  lane: SourcingLane,
  file: File,
  classification: string,
  reason: string,
) {
  const body = new FormData();
  body.set("evidence_id", crypto.randomUUID());
  body.set("expected_version", String(lane.lock_version));
  body.set("classification", classification);
  body.set("reason", reason);
  body.set("file", file);
  return authorizedRequest<SourcingLane>(`/api/v1/sourcing-lanes/${lane.id}/evidence`, token, {
    method: "POST",
    headers: { "idempotency-key": crypto.randomUUID() },
    body,
  });
}

export function decideSourcingLane(
  token: string,
  lane: SourcingLane,
  task: ReviewTask,
  decision: "approve" | "hold",
  reason: string,
) {
  return authorizedRequest<SourcingLane>(`/api/v1/sourcing-lanes/${lane.id}/decision`, token, {
    method: "POST",
    headers: { "content-type": "application/json", "idempotency-key": crypto.randomUUID() },
    body: JSON.stringify({
      decision,
      reason,
      task_id: task.id,
      expected_version: lane.lock_version,
    }),
  });
}
