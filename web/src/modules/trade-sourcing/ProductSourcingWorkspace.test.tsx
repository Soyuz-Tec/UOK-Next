import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { expect, test, vi } from "vitest";

import { ProductSourcingWorkspace } from "./ProductSourcingWorkspace";

test("loads approved references and exposes the governed sourcing-lane command", async () => {
  vi.spyOn(globalThis, "fetch").mockImplementation((input) => {
    const url = String(input);
    let data: object | object[] = [];

    if (url.includes("/location-references/major-seaports/countries")) {
      data = {
        catalog_version: "2026-08-13-testcatalog",
        items: [{ country_code: "GH", country_name: "Ghana", port_count: 2 }],
      };
    } else if (url.includes("/location-references/major-seaports")) {
      data = {
        catalog_version: "2026-08-13-testcatalog",
        items: [
          {
            reference_code: "GHTKD",
            country_code: "GH",
            country_name: "Ghana",
            name: "Takoradi",
            harbor_scale: "medium",
            catalog_number: "46040",
          },
          {
            reference_code: "GHTEM",
            country_code: "GH",
            country_name: "Ghana",
            name: "Tema",
            harbor_scale: "small",
            catalog_number: "46070",
          },
        ],
      };
    } else if (url.includes("/parties")) {
      data = [
        {
          id: "11111111-1111-4111-8111-111111111111",
          stable_identifier: "supplier-001",
          legal_name: "Governed Supplier",
          country_code: "GH",
          party_kind: "organization",
          status: "approved",
          lock_version: 3,
        },
      ];
    } else if (url.includes("/products")) {
      data = [
        {
          id: "22222222-2222-4222-8222-222222222222",
          stable_identifier: "product-001",
          name: "Governed Product",
          product_kind: "commodity",
          base_unit_code: "MT",
          status: "active",
        },
      ];
    } else if (url.includes("/locations")) {
      data = [
        {
          id: "33333333-3333-4333-8333-333333333333",
          stable_identifier: "origin-001",
          name: "Origin",
          country_code: "GH",
          location_kind: "port",
          status: "active",
        },
        {
          id: "44444444-4444-4444-8444-444444444444",
          stable_identifier: "destination-001",
          name: "Destination",
          country_code: "GB",
          location_kind: "port",
          status: "active",
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
    <ProductSourcingWorkspace
      token="signed-token"
      tenantId="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
      onSignOut={vi.fn()}
    />,
  );

  expect(await screen.findByRole("heading", { name: "Create sourcing lane" })).toBeVisible();
  expect(screen.getByRole("option", { name: "Governed Supplier" })).toBeVisible();
  expect(screen.getByRole("option", { name: "Governed Product · MT" })).toBeVisible();
  expect(screen.getByRole("button", { name: "Create governed lane" })).toBeEnabled();

  const user = userEvent.setup();
  await user.selectOptions(
    screen.getByRole("combobox", { name: /Origin or destination country/ }),
    "GH",
  );
  await user.selectOptions(
    await screen.findByRole("combobox", { name: /Standard seaport/ }),
    "GHTEM",
  );

  expect(screen.getAllByText("GHTEM").length).toBeGreaterThan(0);
  expect(screen.getByRole("button", { name: "Create active seaport" })).toBeEnabled();
  expect(fetch).toHaveBeenCalledWith(
    expect.stringContaining("/api/v1/sourcing-lanes"),
    expect.objectContaining({
      headers: expect.objectContaining({ authorization: "Bearer signed-token" }),
    }),
  );
});
