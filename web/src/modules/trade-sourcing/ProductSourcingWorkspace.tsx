import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";

import {
  listParties,
  listReviewTasks,
  type Party,
  type ReviewTask,
} from "../master-parties/partyApi";
import { CreateSourcingLaneForm } from "./CreateSourcingLaneForm";
import { LaneDecisionPanel } from "./LaneDecisionPanel";
import { ReferenceSetupPanel } from "./ReferenceSetupPanel";
import {
  createLocation,
  createProduct,
  listLocations,
  listProducts,
  type Location,
  type LocationInput,
  type Product,
  type ProductInput,
} from "./referenceApi";
import {
  createSourcingLane,
  decideSourcingLane,
  listSourcingLanes,
  uploadSourcingEvidence,
  type SourcingLane,
  type SourcingLaneInput,
} from "./sourcingApi";

type Props = { token: string; tenantId: string; onSignOut: () => void };

const emptyLane: SourcingLaneInput = {
  stable_identifier: "",
  name: "",
  supplier_party_id: "",
  product_id: "",
  origin_location_id: "",
  destination_location_id: "",
  reason: "Establish governed product sourcing lane",
};

export function ProductSourcingWorkspace({ token, tenantId, onSignOut }: Props) {
  const [parties, setParties] = useState<Party[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [locations, setLocations] = useState<Location[]>([]);
  const [lanes, setLanes] = useState<SourcingLane[]>([]);
  const [tasks, setTasks] = useState<ReviewTask[]>([]);
  const [selectedId, setSelectedId] = useState<string>();
  const [laneForm, setLaneForm] = useState(emptyLane);
  const [file, setFile] = useState<File>();
  const [evidenceReason, setEvidenceReason] = useState("Attach sourcing authority evidence");
  const [decisionReason, setDecisionReason] = useState("Evidence supports this sourcing authority");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  const refresh = useCallback(async () => {
    const [nextParties, nextProducts, nextLocations, nextLanes, nextTasks] = await load(token);
    setParties(approved(nextParties));
    setProducts(nextProducts);
    setLocations(nextLocations);
    setLanes(nextLanes);
    setTasks(nextTasks);
    setSelectedId((current) => current ?? nextLanes[0]?.id);
  }, [token]);

  useEffect(() => {
    let active = true;
    void load(token)
      .then(([nextParties, nextProducts, nextLocations, nextLanes, nextTasks]) => {
        if (!active) return;
        setParties(approved(nextParties));
        setProducts(nextProducts);
        setLocations(nextLocations);
        setLanes(nextLanes);
        setTasks(nextTasks);
        setSelectedId(nextLanes[0]?.id);
      })
      .catch((reason: unknown) => {
        if (active) setError(message(reason, "Workspace could not be loaded"));
      });
    return () => {
      active = false;
    };
  }, [token]);

  const selected = useMemo(() => lanes.find((lane) => lane.id === selectedId), [lanes, selectedId]);
  const selectedTask = tasks.find((task) => task.subject_id === selected?.id);
  const readyForLane = parties.length > 0 && products.length > 0 && locations.length > 1;

  async function command(operation: () => Promise<void>) {
    setBusy(true);
    setError(undefined);
    try {
      await operation();
    } catch (reason) {
      setError(message(reason, "The command was rejected"));
    } finally {
      setBusy(false);
    }
  }

  function createReference<T>(operation: () => Promise<T>) {
    return command(async () => {
      await operation();
      await refresh();
    });
  }

  function submitLane(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    void command(async () => {
      const lane = await createSourcingLane(token, laneForm);
      setSelectedId(lane.id);
      setLaneForm(emptyLane);
      await refresh();
    });
  }

  function submitEvidence(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (selected === undefined || file === undefined) return;
    void command(async () => {
      await uploadSourcingEvidence(token, selected, file, "confidential", evidenceReason);
      setFile(undefined);
      await refresh();
    });
  }

  function decide(decision: "approve" | "hold") {
    if (selected === undefined || selectedTask === undefined) return;
    void command(async () => {
      await decideSourcingLane(token, selected, selectedTask, decision, decisionReason);
      await refresh();
    });
  }

  return (
    <section className="sourcing-workspace" id="product-sourcing" aria-labelledby="sourcing-title">
      <header className="workspace-heading">
        <div>
          <span className="eyebrow">Gate 3 · product sourcing authority</span>
          <h1 id="sourcing-title">Build a route the business can trust.</h1>
          <p>Tenant {tenantId.slice(0, 8)}… · approved parties and active references only.</p>
        </div>
        <button className="button-secondary" type="button" onClick={onSignOut}>
          Sign out
        </button>
      </header>

      <div className="workflow-steps" aria-label="Sourcing authority stages">
        {[
          ["01", "References", "Product and locations"],
          ["02", "Lane", "Approved supplier route"],
          ["03", "Evidence", "Verified source bytes"],
          ["04", "Decision", "Approve or hold"],
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
      <ReferenceSetupPanel
        busy={busy}
        onProduct={(input: ProductInput) => createReference(() => createProduct(token, input))}
        onLocation={(input: LocationInput) => createReference(() => createLocation(token, input))}
      />

      <div className="sourcing-grid">
        <aside className="lane-list" aria-label="Sourcing lanes">
          <div className="panel-heading">
            <div>
              <span className="eyebrow">Authority portfolio</span>
              <h2>Sourcing lanes</h2>
            </div>
            <span className="count-badge">{lanes.length}</span>
          </div>
          {lanes.length === 0 ? (
            <p className="empty-state">Create the first governed lane.</p>
          ) : null}
          {lanes.map((lane) => (
            <button
              className={lane.id === selectedId ? "party-row party-row--active" : "party-row"}
              key={lane.id}
              type="button"
              onClick={() => setSelectedId(lane.id)}
            >
              <span>
                <strong>{lane.name}</strong>
                <small>{lane.stable_identifier}</small>
              </span>
              <span className={`status status--${lane.status}`}>{lane.status}</span>
            </button>
          ))}
        </aside>

        <div className="work-panel">
          {selected === undefined ? (
            <CreateSourcingLaneForm
              busy={busy}
              form={laneForm}
              locations={locations}
              parties={parties}
              products={products}
              ready={readyForLane}
              onChange={setLaneForm}
              onSubmit={submitLane}
            />
          ) : (
            <LaneDecisionPanel
              lane={selected}
              task={selectedTask}
              busy={busy}
              file={file}
              evidenceReason={evidenceReason}
              decisionReason={decisionReason}
              onFile={setFile}
              onEvidenceReason={setEvidenceReason}
              onDecisionReason={setDecisionReason}
              onEvidence={submitEvidence}
              onDecision={decide}
            />
          )}
        </div>
      </div>
    </section>
  );
}

function load(token: string) {
  return Promise.all([
    listParties(token),
    listProducts(token),
    listLocations(token),
    listSourcingLanes(token),
    listReviewTasks(token),
  ]);
}

function approved(parties: Party[]) {
  return parties.filter((party) => party.status === "approved");
}

function message(reason: unknown, fallback: string) {
  return reason instanceof Error ? reason.message : fallback;
}
