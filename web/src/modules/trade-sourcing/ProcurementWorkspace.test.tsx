import { render, screen } from "@testing-library/react";
import { expect, test, vi } from "vitest";

import { ProcurementWorkspace } from "./ProcurementWorkspace";

test("renders the governed requisition to comparison command path", async () => {
  vi.spyOn(globalThis, "fetch").mockImplementation((input) => {
    const url = String(input);
    let data: object[] = [];

    if (url.includes("/sourcing-lanes")) {
      data = [
        {
          id: "11111111-1111-4111-8111-111111111111",
          stable_identifier: "lane-001",
          name: "Approved Lane",
          supplier_party_id: "22222222-2222-4222-8222-222222222222",
          product_id: "33333333-3333-4333-8333-333333333333",
          origin_location_id: "44444444-4444-4444-8444-444444444444",
          destination_location_id: "55555555-5555-4555-8555-555555555555",
          status: "approved",
          lock_version: 3,
        },
      ];
    } else if (url.includes("/parties")) {
      data = [
        {
          id: "22222222-2222-4222-8222-222222222222",
          stable_identifier: "supplier-001",
          legal_name: "Approved Supplier",
          country_code: "GH",
          party_kind: "organization",
          status: "approved",
          lock_version: 3,
        },
      ];
    }

    return Promise.resolve(
      new Response(JSON.stringify({ data }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
  });

  render(
    <ProcurementWorkspace
      token="signed-token"
      tenantId="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
      onSignOut={vi.fn()}
    />,
  );

  expect(
    await screen.findByRole("heading", {
      name: "Compare attributable offers, not opaque scores.",
    }),
  ).toBeVisible();
  expect(screen.getByRole("heading", { name: "Purchase requisition" })).toBeVisible();
  expect(screen.getByRole("heading", { name: "Open RFQ" })).toBeVisible();
  expect(screen.getByRole("heading", { name: "Record quote" })).toBeVisible();
  expect(screen.getByRole("option", { name: "Approved Lane" })).toBeVisible();
  expect(fetch).toHaveBeenCalledWith(
    expect.stringContaining("/api/v1/quote-comparisons"),
    expect.objectContaining({
      headers: expect.objectContaining({ authorization: "Bearer signed-token" }),
    }),
  );
});
