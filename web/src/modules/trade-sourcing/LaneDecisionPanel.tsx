import type { FormEvent } from "react";

import type { ReviewTask } from "../master-parties/partyApi";
import type { SourcingLane } from "./sourcingApi";

type Props = {
  lane: SourcingLane;
  task: ReviewTask | undefined;
  busy: boolean;
  file: File | undefined;
  evidenceReason: string;
  decisionReason: string;
  onFile: (file?: File) => void;
  onEvidenceReason: (reason: string) => void;
  onDecisionReason: (reason: string) => void;
  onEvidence: (event: FormEvent<HTMLFormElement>) => void;
  onDecision: (decision: "approve" | "hold") => void;
};

export function LaneDecisionPanel(props: Props) {
  const { lane, task, busy } = props;

  return (
    <>
      <div className="panel-heading">
        <div>
          <span className="eyebrow">Selected authority</span>
          <h2>{lane.name}</h2>
        </div>
        <span className={`status status--${lane.status}`}>{lane.status}</span>
      </div>
      <dl className="record-facts">
        <div>
          <dt>Identifier</dt>
          <dd>{lane.stable_identifier}</dd>
        </div>
        <div>
          <dt>Version</dt>
          <dd>{lane.lock_version}</dd>
        </div>
      </dl>
      {lane.status === "draft" || lane.status === "hold" ? (
        <form className="command-form" onSubmit={props.onEvidence}>
          <h3>Submit sourcing evidence</h3>
          <label>
            Evidence file
            <input
              type="file"
              required
              onChange={(event) => props.onFile(event.currentTarget.files?.[0])}
            />
          </label>
          <label>
            Reason
            <textarea
              required
              minLength={3}
              maxLength={500}
              value={props.evidenceReason}
              onChange={(event) => props.onEvidenceReason(event.currentTarget.value)}
            />
          </label>
          <button disabled={busy || props.file === undefined}>Verify and submit</button>
        </form>
      ) : null}
      {lane.status === "evidence_submitted" && task !== undefined ? (
        <div className="command-form">
          <h3>Human review decision</h3>
          <p>
            Task {task.id.slice(0, 8)}… is bound to version {task.subject_version}.
          </p>
          <label>
            Decision reason
            <textarea
              required
              minLength={3}
              maxLength={500}
              value={props.decisionReason}
              onChange={(event) => props.onDecisionReason(event.currentTarget.value)}
            />
          </label>
          <div className="decision-actions">
            <button disabled={busy} onClick={() => props.onDecision("approve")}>
              Approve lane
            </button>
            <button
              className="button-hold"
              disabled={busy}
              onClick={() => props.onDecision("hold")}
            >
              Place on hold
            </button>
          </div>
        </div>
      ) : null}
      {lane.status === "approved" ? (
        <div className="decision-result">
          <strong>Sourcing authority approved</strong>
          <p>
            Product, supplier, route, evidence, and exact human decision are tenant-bound and
            attributable.
          </p>
        </div>
      ) : null}
    </>
  );
}
