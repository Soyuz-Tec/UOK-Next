import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { expect, test, vi } from "vitest";

import { UserAccessWorkspace } from "./UserAccessWorkspace";

test("creates a role-bounded user and exposes the one-time handoff", async () => {
  const user = userEvent.setup();

  vi.spyOn(globalThis, "fetch").mockImplementation((input, init) => {
    const url = String(input);
    const method = init?.method ?? "GET";

    if (url.includes("access-profiles")) {
      return Promise.resolve(
        jsonResponse([
          {
            key: "entity_onboarding_operator",
            label: "Entity onboarding operator",
            permissions: ["parties:create"],
          },
        ]),
      );
    }

    if (method === "POST") {
      return Promise.resolve(
        jsonResponse(
          {
            id: "actor-id",
            username: "onboarding.operator",
            display_name: "Onboarding Operator",
            access_profile: "entity_onboarding_operator",
            status: "pending_activation",
            must_change_password: true,
            lock_version: 1,
          },
          201,
        ),
      );
    }

    return Promise.resolve(jsonResponse([]));
  });

  render(
    <UserAccessWorkspace
      token="administrator-token"
      tenantId="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
      onSignOut={vi.fn()}
    />,
  );

  await screen.findByRole("heading", { name: "Create an onboarding user" });
  await user.type(screen.getByLabelText("Username"), "onboarding.operator");
  await user.type(screen.getByLabelText("Display name"), "Onboarding Operator");
  const password = screen.getByLabelText("Temporary password");
  await user.clear(password);
  await user.type(password, "Temporary passphrase 2026!");
  await user.click(screen.getByRole("button", { name: "Create user" }));

  expect(await screen.findByText("Hand access to @onboarding.operator")).toBeVisible();
  expect(screen.getByLabelText("Temporary password")).toHaveTextContent(
    "Temporary passphrase 2026!",
  );
  expect(fetch).toHaveBeenCalledWith(
    "/api/v1/identity/users",
    expect.objectContaining({
      headers: expect.objectContaining({ authorization: "Bearer administrator-token" }),
    }),
  );
});

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify({ data }), {
    status,
    headers: { "content-type": "application/json" },
  });
}
