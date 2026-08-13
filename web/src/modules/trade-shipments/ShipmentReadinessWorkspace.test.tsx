import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, expect, test, vi } from "vitest";

import { ShipmentReadinessWorkspace } from "./ShipmentReadinessWorkspace";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

const proposal = {
  id: "11111111-1111-4111-8111-111111111111",
  stable_identifier: "proposal-001",
  quote_comparison_id: "22222222-2222-4222-8222-222222222222",
  source_snapshot: {},
  status: "approved",
  lock_version: 4,
};

const readinessCase = {
  id: "33333333-3333-4333-8333-333333333333",
  stable_identifier: "readiness-001",
  purchase_commitment_proposal_id: proposal.id,
  purchase_commitment_proposal_version: 4,
  source_snapshot: {
    readiness_formula_version: 1,
    purchase_commitment_proposal_id: proposal.id,
    purchase_commitment_proposal_version: 4,
    proposal_evidence: {
      evidence_id: "44444444-4444-4444-8444-444444444444",
      sha256: "abcdef1234567890",
      classification: "confidential",
    },
    commercial_source: {
      supplier_party_id: "55555555-5555-4555-8555-555555555555",
      quantity: "25",
      unit_code: "MT",
      unit_price: "90",
      total_price: "2250",
      currency_code: "USD",
      required_by: "2026-09-30",
    },
  },
  checklist_snapshot: {
    formula_version: 1,
    checks: [
      { code: "approved_proposal", status: "passed", authority: "server" },
      { code: "current_commercial_source", status: "passed", authority: "server" },
      { code: "verified_commercial_evidence", status: "passed", authority: "server" },
      {
        code: "verified_operational_readiness_evidence",
        status: "passed",
        authority: "server",
      },
    ],
  },
  status: "awaiting_review",
  evidence_metadata: {
    evidence_id: "66666666-6666-4666-8666-666666666666",
    sha256: "readiness1234567890",
    classification: "confidential",
  },
  decision_reason: null,
  lock_version: 2,
  shipment_created: false,
  dispatch_created: false,
  inventory_effect_created: false,
  finance_effect_created: false,
  external_effect_created: false,
};

function response(data: object | object[]) {
  return Promise.resolve(
    new Response(JSON.stringify({ data }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
}

test("opens one source-bound gate without commercial term re-entry", async () => {
  const bodies: string[] = [];
  vi.spyOn(globalThis, "fetch").mockImplementation((input, init) => {
    const url = String(input);
    if (url.includes("/purchase-commitment-proposals")) return response([proposal]);
    if (url.includes("/shipment-readiness-cases") && init?.method === "POST") {
      bodies.push(String(init.body));
      return response(readinessCase);
    }
    return response([]);
  });

  const user = userEvent.setup();
  render(
    <ShipmentReadinessWorkspace
      token="signed-token"
      tenantId="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
      onSignOut={vi.fn()}
    />,
  );

  expect(await screen.findByRole("option", { name: "proposal-001" })).toBeVisible();
  await user.click(screen.getByRole("button", { name: "Open readiness gate" }));

  await waitFor(() => expect(bodies).toHaveLength(1));
  const command = JSON.parse(bodies[0] ?? "{}") as Record<string, unknown>;
  expect(command).toMatchObject({
    purchase_commitment_proposal_id: proposal.id,
    expected_proposal_version: 4,
  });
  expect(command).not.toHaveProperty("quantity");
  expect(command).not.toHaveProperty("unit_price");
  expect(command).not.toHaveProperty("supplier_party_id");
});

test("shows exact source, server checks, and GO or HOLD actions", async () => {
  vi.spyOn(globalThis, "fetch").mockImplementation((input) => {
    const url = String(input);
    if (url.includes("/purchase-commitment-proposals")) return response([proposal]);
    if (url.includes("/shipment-readiness-cases")) return response([readinessCase]);
    if (url.includes("/review-tasks")) {
      return response([
        {
          id: "77777777-7777-4777-8777-777777777777",
          subject_id: readinessCase.id,
          status: "open",
          lock_version: 1,
        },
      ]);
    }
    if (url.includes("/parties")) {
      return response([
        {
          id: readinessCase.source_snapshot.commercial_source.supplier_party_id,
          legal_name: "Approved Supplier",
        },
      ]);
    }
    return response([]);
  });

  render(
    <ShipmentReadinessWorkspace
      token="signed-token"
      tenantId="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
      onSignOut={vi.fn()}
    />,
  );

  expect(await screen.findByText("readiness-001")).toBeVisible();
  expect(screen.getByText("Approved Supplier")).toBeVisible();
  expect(screen.getByText("Operational readiness evidence")).toBeVisible();
  expect(screen.getByRole("button", { name: "HOLD" })).toBeEnabled();
  expect(screen.getByRole("button", { name: "Record GO" })).toBeEnabled();
  expect(screen.getByText(/three actions, zero term re-entry, zero side effects/)).toBeVisible();
});
