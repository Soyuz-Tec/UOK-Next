export type ReviewTask = {
  id: string;
  subject_id: string;
  subject_version: number;
  status: "open" | "completed";
  resolution: "approve" | "hold" | null;
};

export type EvidenceObject = {
  id: string;
  content_type: string;
  byte_size: number;
  sha256: string;
  classification: string;
  state: "pending_upload" | "verified";
};

export type Party = {
  id: string;
  stable_identifier: string;
  legal_name: string;
  country_code: string;
  party_kind: "organization" | "individual";
  status: "draft" | "evidence_submitted" | "approved" | "hold";
  lock_version: number;
  review_task?: ReviewTask;
  evidence_objects?: EvidenceObject[];
};

export type CreatePartyInput = {
  stable_identifier: string;
  legal_name: string;
  country_code: string;
  party_kind: Party["party_kind"];
  reason: string;
};

export function listParties(token: string): Promise<Party[]> {
  return authorizedRequest<Party[]>("/api/v1/parties?limit=100", token);
}

export function listReviewTasks(token: string): Promise<ReviewTask[]> {
  return authorizedRequest<ReviewTask[]>("/api/v1/review-tasks", token);
}

export function createParty(token: string, input: CreatePartyInput): Promise<Party> {
  return authorizedRequest<Party>("/api/v1/parties", token, {
    method: "POST",
    headers: { "content-type": "application/json", "idempotency-key": crypto.randomUUID() },
    body: JSON.stringify(input),
  });
}

export function uploadEvidence(
  token: string,
  party: Party,
  file: File,
  classification: string,
  reason: string,
): Promise<Party> {
  const form = new FormData();
  form.set("evidence_id", crypto.randomUUID());
  form.set("expected_version", String(party.lock_version));
  form.set("classification", classification);
  form.set("reason", reason);
  form.set("file", file);

  return authorizedRequest<Party>(`/api/v1/parties/${party.id}/evidence`, token, {
    method: "POST",
    headers: { "idempotency-key": crypto.randomUUID() },
    body: form,
  });
}

export function decideParty(
  token: string,
  party: Party,
  task: ReviewTask,
  decision: "approve" | "hold",
  reason: string,
): Promise<Party> {
  return authorizedRequest<Party>(`/api/v1/parties/${party.id}/decision`, token, {
    method: "POST",
    headers: { "content-type": "application/json", "idempotency-key": crypto.randomUUID() },
    body: JSON.stringify({
      decision,
      reason,
      task_id: task.id,
      expected_version: party.lock_version,
    }),
  });
}
import { authorizedRequest } from "../../shared/authorizedApi";
