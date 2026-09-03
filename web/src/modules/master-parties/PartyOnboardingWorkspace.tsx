import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";

import { CreatePartyForm } from "./CreatePartyForm";
import { emptyPartyForm } from "./partyForm";
import {
  createParty,
  decideParty,
  listParties,
  listReviewTasks,
  uploadEvidence,
  type Party,
  type ReviewTask,
} from "./partyApi";

type Props = { token: string; tenantId: string; permissions: string[]; onSignOut: () => void };

export function PartyOnboardingWorkspace({ token, tenantId, permissions, onSignOut }: Props) {
  const [parties, setParties] = useState<Party[]>([]);
  const [tasks, setTasks] = useState<ReviewTask[]>([]);
  const [selectedId, setSelectedId] = useState<string>();
  const [partyForm, setPartyForm] = useState(emptyPartyForm);
  const [file, setFile] = useState<File>();
  const [classification, setClassification] = useState("confidential");
  const [evidenceReason, setEvidenceReason] = useState("Attach registration evidence for review");
  const [decisionReason, setDecisionReason] = useState(
    "Evidence reviewed against onboarding policy",
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const canCreate = permissions.includes("parties:create");
  const canSubmitEvidence = permissions.includes("parties:evidence:submit");
  const canReview = permissions.includes("parties:approve");
  const canReadTasks = permissions.includes("workflow:tasks:read");

  const loadTasks = useCallback(
    () => (canReadTasks ? listReviewTasks(token) : Promise.resolve([])),
    [canReadTasks, token],
  );

  const refresh = useCallback(async () => {
    const [nextParties, nextTasks] = await Promise.all([listParties(token), loadTasks()]);
    setParties(nextParties);
    setTasks(nextTasks);
    setSelectedId((current) => current ?? nextParties[0]?.id);
  }, [loadTasks, token]);

  useEffect(() => {
    let active = true;

    void Promise.all([listParties(token), loadTasks()])
      .then(([nextParties, nextTasks]) => {
        if (!active) return;
        setParties(nextParties);
        setTasks(nextTasks);
        setSelectedId(nextParties[0]?.id);
      })
      .catch((reason: unknown) => {
        if (active) {
          setError(reason instanceof Error ? reason.message : "Workspace could not be loaded");
        }
      });

    return () => {
      active = false;
    };
  }, [loadTasks, token]);

  const selected = useMemo(
    () => parties.find((party) => party.id === selectedId),
    [parties, selectedId],
  );
  const selectedTask = tasks.find((task) => task.subject_id === selected?.id);

  async function perform(operation: () => Promise<Party>) {
    setBusy(true);
    setError(undefined);
    try {
      const updated = await operation();
      setSelectedId(updated.id);
      await refresh();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "The command was rejected");
    } finally {
      setBusy(false);
    }
  }

  async function submitParty(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    await perform(() => createParty(token, partyForm));
    setPartyForm(emptyPartyForm);
  }

  async function submitEvidence(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (selected === undefined || file === undefined) return;
    await perform(() => uploadEvidence(token, selected, file, classification, evidenceReason));
    setFile(undefined);
    event.currentTarget.reset();
  }

  function decide(decision: "approve" | "hold") {
    if (selected === undefined || selectedTask === undefined) return;
    void perform(() => decideParty(token, selected, selectedTask, decision, decisionReason));
  }

  return (
    <section
      className="onboarding-workspace"
      id="party-onboarding"
      aria-labelledby="workspace-title"
    >
      <header className="workspace-heading">
        <div>
          <span className="eyebrow">Gate 3 · party onboarding</span>
          <h1 id="workspace-title">From draft to attributable decision.</h1>
          <p>Tenant {tenantId.slice(0, 8)}… · every mutation is policy checked and recorded.</p>
        </div>
        <button className="button-secondary" type="button" onClick={onSignOut}>
          Sign out
        </button>
      </header>

      <div className="workflow-steps" aria-label="Onboarding stages">
        {[
          ["01", "Create", "Governed party draft"],
          ["02", "Evidence", "Verified object bytes"],
          ["03", "Review", "Exact human task"],
          ["04", "Decision", "Approve or hold"],
        ].map(([number, title, detail]) => (
          <div key={number}>
            <span>{number}</span>
            <strong>{title}</strong>
            <small>{detail}</small>
          </div>
        ))}
      </div>

      {error === undefined ? null : <div className="workspace-error">{error}</div>}

      <div className="workspace-grid">
        <aside className="party-list" aria-label="Onboarding parties">
          <div className="panel-heading">
            <div>
              <span className="eyebrow">Portfolio</span>
              <h2>Parties</h2>
            </div>
            <span className="count-badge">{parties.length}</span>
          </div>
          {parties.length === 0 ? <p className="empty-state">No party drafts yet.</p> : null}
          {parties.map((party) => (
            <button
              className={party.id === selectedId ? "party-row party-row--active" : "party-row"}
              key={party.id}
              type="button"
              onClick={() => setSelectedId(party.id)}
            >
              <span>
                <strong>{party.legal_name}</strong>
                <small>{party.stable_identifier}</small>
              </span>
              <span className={`status status--${party.status}`}>{party.status}</span>
            </button>
          ))}
        </aside>

        <div className="work-panel">
          {selected === undefined && canCreate ? (
            <CreatePartyForm
              form={partyForm}
              busy={busy}
              onChange={setPartyForm}
              onSubmit={submitParty}
            />
          ) : selected === undefined ? (
            <p className="empty-state">No party is available for your assigned access.</p>
          ) : (
            <>
              <div className="panel-heading">
                <div>
                  <span className="eyebrow">Selected record</span>
                  <h2>{selected.legal_name}</h2>
                </div>
                <span className={`status status--${selected.status}`}>{selected.status}</span>
              </div>
              <dl className="record-facts">
                <div>
                  <dt>Identifier</dt>
                  <dd>{selected.stable_identifier}</dd>
                </div>
                <div>
                  <dt>Country</dt>
                  <dd>{selected.country_code}</dd>
                </div>
                <div>
                  <dt>Kind</dt>
                  <dd>{selected.party_kind}</dd>
                </div>
                <div>
                  <dt>Version</dt>
                  <dd>{selected.lock_version}</dd>
                </div>
              </dl>

              {(selected.status === "draft" || selected.status === "hold") && canSubmitEvidence ? (
                <form className="command-form" onSubmit={(event) => void submitEvidence(event)}>
                  <h3>Submit evidence</h3>
                  <label>
                    Evidence file
                    <input
                      type="file"
                      required
                      onChange={(event) => setFile(event.currentTarget.files?.[0])}
                    />
                  </label>
                  <label>
                    Classification
                    <select
                      value={classification}
                      onChange={(event) => setClassification(event.currentTarget.value)}
                    >
                      <option value="internal">Internal</option>
                      <option value="confidential">Confidential</option>
                      <option value="restricted">Restricted</option>
                    </select>
                  </label>
                  <label>
                    Reason
                    <textarea
                      required
                      minLength={3}
                      maxLength={500}
                      value={evidenceReason}
                      onChange={(event) => setEvidenceReason(event.currentTarget.value)}
                    />
                  </label>
                  <button disabled={busy || file === undefined}>Verify and submit</button>
                </form>
              ) : null}

              {selected.status === "evidence_submitted" &&
              selectedTask !== undefined &&
              canReview ? (
                <div className="command-form">
                  <h3>Human review decision</h3>
                  <p>
                    Task {selectedTask.id.slice(0, 8)}… is bound to version{" "}
                    {selectedTask.subject_version}.
                  </p>
                  <label>
                    Decision reason
                    <textarea
                      required
                      minLength={3}
                      maxLength={500}
                      value={decisionReason}
                      onChange={(event) => setDecisionReason(event.currentTarget.value)}
                    />
                  </label>
                  <div className="decision-actions">
                    <button disabled={busy} onClick={() => decide("approve")}>
                      Approve onboarding
                    </button>
                    <button className="button-hold" disabled={busy} onClick={() => decide("hold")}>
                      Place on hold
                    </button>
                  </div>
                </div>
              ) : null}

              {selected.status === "approved" ? (
                <div className="decision-result">
                  <strong>Onboarding approved</strong>
                  <p>
                    The decision, task completion, audit evidence, and outbox events committed
                    together.
                  </p>
                </div>
              ) : null}
            </>
          )}
        </div>
      </div>
    </section>
  );
}
