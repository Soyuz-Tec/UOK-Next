import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, expect, test, vi } from "vitest";

import { OperationalReportWorkspace } from "./OperationalReportWorkspace";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

const firstCase = readiness("11111111-1111-4111-8111-111111111111", "readiness-latest", "go", 3);
const secondCase = readiness(
  "22222222-2222-4222-8222-222222222222",
  "readiness-earlier",
  "hold",
  5,
);

test("loads the latest completed report and exposes lineage without mutation controls", async () => {
  const requests: string[] = [];
  vi.spyOn(globalThis, "fetch").mockImplementation((input) => {
    const url = String(input);
    requests.push(url);

    if (url.includes("/shipment-readiness-cases")) return response([firstCase, secondCase]);
    return response(report(firstCase.id, "ready"));
  });

  render(
    <OperationalReportWorkspace
      token="signed-token"
      tenantId="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
      onSignOut={vi.fn()}
    />,
  );

  expect(await screen.findByRole("heading", { name: "Qualified sourcing lane" })).toBeVisible();
  expect(screen.getByText("ready")).toBeVisible();
  expect(screen.getAllByRole("table")).toHaveLength(2);
  expect(screen.getByText(/Decision intelligence, never transaction authority/)).toBeVisible();
  expect(screen.getByText("Business mutation authorized: No")).toBeVisible();
  expect(screen.queryByRole("button", { name: /approve|hold|go|create|submit/i })).toBeNull();
  expect(requests).toContain(
    `/api/v1/operational-reports/${firstCase.id}?expected_version=${firstCase.lock_version}`,
  );
});

test("switches report in one selection and clears stale content after a failed read", async () => {
  let rejectSecond = false;
  vi.spyOn(globalThis, "fetch").mockImplementation((input) => {
    const url = String(input);
    if (url.includes("/shipment-readiness-cases")) return response([firstCase, secondCase]);
    if (url.includes(secondCase.id) && rejectSecond) {
      return Promise.resolve(
        new Response(JSON.stringify({ error: { message: "Source reconciliation failed" } }), {
          status: 409,
          headers: { "content-type": "application/json" },
        }),
      );
    }
    return response(report(url.includes(secondCase.id) ? secondCase.id : firstCase.id, "ready"));
  });

  const user = userEvent.setup();
  render(
    <OperationalReportWorkspace
      token="signed-token"
      tenantId="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
      onSignOut={vi.fn()}
    />,
  );

  expect(await screen.findByRole("heading", { name: "Qualified sourcing lane" })).toBeVisible();
  rejectSecond = true;
  await user.selectOptions(screen.getByLabelText("Report case"), secondCase.id);

  expect(await screen.findByRole("alert")).toHaveTextContent("Source reconciliation failed");
  expect(screen.getByRole("alert")).toHaveTextContent("No stale or partial report is shown");
  await waitFor(() =>
    expect(screen.queryByRole("heading", { name: "Qualified sourcing lane" })).toBeNull(),
  );
  expect(screen.getByRole("button", { name: "Retry current report" })).toBeEnabled();
});

function readiness(id: string, stableIdentifier: string, status: "go" | "hold", version: number) {
  return {
    id,
    stable_identifier: stableIdentifier,
    purchase_commitment_proposal_id: "33333333-3333-4333-8333-333333333333",
    purchase_commitment_proposal_version: 4,
    source_snapshot: {},
    checklist_snapshot: { formula_version: 1, checks: [] },
    status,
    evidence_metadata: {},
    decision_reason: "reviewed",
    lock_version: version,
    shipment_created: false,
    dispatch_created: false,
    inventory_effect_created: false,
    finance_effect_created: false,
    external_effect_created: false,
  };
}

function report(readinessId: string, outcome: "ready" | "held") {
  return {
    definition_version: 1,
    projection_id: "a".repeat(64),
    grain: { type: "shipment_readiness_case", id: readinessId, version: 3 },
    outcome,
    stages: [
      {
        code: "party_onboarding",
        source_type: "party",
        source_id: "44444444-4444-4444-8444-444444444444",
        source_version: 3,
        status: "approved",
      },
    ],
    dimensions: {
      supplier: {
        id: "44444444-4444-4444-8444-444444444444",
        stable_identifier: "supplier-001",
        legal_name: "Qualified supplier",
        country_code: "GH",
      },
      product: {
        id: "55555555-5555-4555-8555-555555555555",
        stable_identifier: "product-001",
        name: "Product",
        base_unit_code: "MT",
      },
      origin: {
        id: "66666666-6666-4666-8666-666666666666",
        stable_identifier: "origin-001",
        name: "Origin",
        location_kind: "port",
        country_code: "GH",
      },
      destination: {
        id: "77777777-7777-4777-8777-777777777777",
        stable_identifier: "destination-001",
        name: "Destination",
        location_kind: "port",
        country_code: "IN",
      },
      sourcing_lane: {
        id: "88888888-8888-4888-8888-888888888888",
        stable_identifier: "lane-001",
        name: "Qualified sourcing lane",
      },
    },
    metrics: {
      commercial: {
        grain: "approved_selected_quote",
        quantity: "25",
        unit_code: "MT",
        unit_price: "90",
        approved_total: "2250",
        currency_code: "USD",
        delivery_days: 12,
        required_by: "2026-09-30",
        currency_conversion_applied: false,
      },
      lineage: { verified_evidence_count: 1, audit_event_count: 1, delivery_event_count: 1 },
    },
    evidence_lineage: [
      {
        stage: "party_onboarding",
        evidence_id: "99999999-9999-4999-8999-999999999999",
        sha256: "b".repeat(64),
        classification: "confidential",
        state: "verified",
      },
    ],
    audit_events: [
      {
        id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        action: "approve",
        resource_type: "party",
        resource_id: "44444444-4444-4444-8444-444444444444",
        outcome: "succeeded",
        reason: "Evidence reviewed",
        classification: "internal",
        actor_id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        correlation_id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
        occurred_at: "2026-08-25T12:00:00Z",
      },
    ],
    delivery_events: [],
    delivery_status_counts: { pending: 1, publishing: 0, published: 0, dead_letter: 0 },
    authority: {
      source_of_truth: false,
      business_mutation_authorized: false,
      external_effect_created: false,
    },
    freshness: {
      observed_at: "2026-08-25T12:00:00Z",
      mode: "live_repeatable_read",
      maximum_staleness_seconds: 0,
    },
    reconciliation: {
      status: "reconciled",
      definition_version: 1,
      projection_sha256: "a".repeat(64),
    },
  };
}

function response(data: object | object[]) {
  return Promise.resolve(
    new Response(JSON.stringify({ data }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
}
