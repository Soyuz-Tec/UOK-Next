import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { expect, test, vi } from "vitest";

import { PasswordActivation } from "./PasswordActivation";

test("replaces the temporary password before entering the workspace", async () => {
  const user = userEvent.setup();
  const completed = vi.fn();
  vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(JSON.stringify({ data: {} })));

  render(
    <PasswordActivation
      session={{
        accessToken: "temporary-session",
        passwordChangeRequired: true,
        identity: {
          tenant_id: "tenant-id",
          actor_id: "actor-id",
          username: "onboarding.operator",
          permissions: ["identity:password:change"],
        },
      }}
      onCompleted={completed}
    />,
  );

  await user.type(screen.getByLabelText("Temporary password"), "Temporary passphrase 2026!");
  await user.type(screen.getByLabelText("New passphrase"), "Private passphrase for 2026!");
  await user.type(screen.getByLabelText("Confirm new passphrase"), "Private passphrase for 2026!");
  await user.click(screen.getByRole("button", { name: "Activate and sign in again" }));

  expect(fetch).toHaveBeenCalledWith(
    "/api/v1/session/password",
    expect.objectContaining({
      headers: expect.objectContaining({ authorization: "Bearer temporary-session" }),
    }),
  );
  expect(completed).toHaveBeenCalledOnce();
});
