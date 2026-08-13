import { render, screen } from "@testing-library/react";
import { expect, test, vi } from "vitest";

import { PurchaseCommitmentWorkspace } from "./PurchaseCommitmentWorkspace";

test("renders a one-selection source-derived commitment workflow", async () => {
  vi.spyOn(globalThis, "fetch").mockImplementation((input) => {
    const url = String(input);
    let data: object[] = [];

    if (url.includes("/quote-comparisons")) {
      data = [
        {
          id: "11111111-1111-4111-8111-111111111111",
          stable_identifier: "comparison-001",
          rfq_id: "22222222-2222-4222-8222-222222222222",
          recommended_quote_id: "33333333-3333-4333-8333-333333333333",
          ranking_snapshot: {
            formula_version: 1,
            ranking: [
              {
                quote_id: "33333333-3333-4333-8333-333333333333",
                supplier_party_id: "44444444-4444-4444-8444-444444444444",
                quote_version: 2,
                quoted_quantity: "25",
                unit_price: "90",
                total_price: "2250",
                currency_code: "USD",
                delivery_days: 21,
              },
            ],
          },
          status: "approved",
          lock_version: 2,
        },
      ];
    } else if (url.includes("/parties")) {
      data = [
        {
          id: "44444444-4444-4444-8444-444444444444",
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
    <PurchaseCommitmentWorkspace
      token="signed-token"
      tenantId="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
      onSignOut={vi.fn()}
    />,
  );

  expect(
    await screen.findByRole("heading", { name: "Propose once from approved source terms." }),
  ).toBeVisible();
  expect(screen.getByRole("option", { name: "comparison-001" })).toBeVisible();
  expect(screen.getByRole("button", { name: "Create source-bound proposal" })).toBeEnabled();
  expect(screen.getByText(/no contract, no external effect\./)).toBeVisible();
  expect(fetch).toHaveBeenCalledWith(
    expect.stringContaining("/api/v1/purchase-commitment-proposals"),
    expect.objectContaining({
      headers: expect.objectContaining({ authorization: "Bearer signed-token" }),
    }),
  );
});
