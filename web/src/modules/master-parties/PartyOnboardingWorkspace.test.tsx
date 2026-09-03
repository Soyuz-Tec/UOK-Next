import { render, screen } from "@testing-library/react";
import { expect, test, vi } from "vitest";

import { PartyOnboardingWorkspace } from "./PartyOnboardingWorkspace";

test("loads tenant-scoped parties and exposes the next governed command", async () => {
  vi.spyOn(globalThis, "fetch").mockImplementation((input) => {
    const url = String(input);
    const data = url.includes("review-tasks")
      ? []
      : [
          {
            id: "11111111-1111-4111-8111-111111111111",
            stable_identifier: "supplier-001",
            legal_name: "Aseda Trading Limited",
            country_code: "GH",
            party_kind: "organization",
            status: "draft",
            lock_version: 1,
          },
        ];

    return Promise.resolve(
      new Response(JSON.stringify({ data }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
  });

  render(
    <PartyOnboardingWorkspace
      token="signed-token"
      tenantId="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
      permissions={[
        "parties:create",
        "parties:evidence:submit",
        "parties:approve",
        "workflow:tasks:read",
      ]}
      onSignOut={vi.fn()}
    />,
  );

  expect(await screen.findAllByText("Aseda Trading Limited")).toHaveLength(2);
  expect(screen.getByRole("heading", { name: "Submit evidence" })).toBeVisible();
  expect(screen.getByLabelText("Evidence file")).toBeVisible();
  expect(fetch).toHaveBeenCalledWith(
    expect.stringContaining("/api/v1/parties"),
    expect.objectContaining({
      headers: expect.objectContaining({ authorization: "Bearer signed-token" }),
    }),
  );
});
