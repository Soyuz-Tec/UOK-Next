import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { expect, test, vi } from "vitest";

import { QualificationSignIn } from "./QualificationSignIn";

test("authenticates an attributable user with username and password by default", async () => {
  const user = userEvent.setup();
  const authenticated = vi.fn();

  vi.spyOn(globalThis, "fetch").mockResolvedValue(sessionResponse());
  render(<QualificationSignIn onAuthenticated={authenticated} />);

  await user.type(screen.getByLabelText("Username"), "onboarding.operator");
  await user.type(screen.getByLabelText("Password"), "A private passphrase 2026!");
  await user.click(screen.getByRole("button", { name: "Enter workspace" }));

  expect(fetch).toHaveBeenCalledWith(
    "/api/v1/session",
    expect.objectContaining({
      body: JSON.stringify({
        username: "onboarding.operator",
        password: "A private passphrase 2026!",
      }),
    }),
  );
  expect(authenticated).toHaveBeenCalledWith(
    expect.objectContaining({ accessToken: "signed-access-token", passwordChangeRequired: false }),
  );
});

test("keeps the protected local access code as an explicit administrator method", async () => {
  const user = userEvent.setup();
  vi.spyOn(globalThis, "fetch").mockResolvedValue(sessionResponse());
  render(<QualificationSignIn onAuthenticated={vi.fn()} />);

  await user.click(screen.getByRole("button", { name: "Administrator access" }));
  await user.type(screen.getByLabelText("Local access code"), "x".repeat(32));
  await user.click(screen.getByRole("button", { name: "Enter workspace" }));

  expect(fetch).toHaveBeenCalledWith(
    "/api/v1/session",
    expect.objectContaining({ body: JSON.stringify({ access_code: "x".repeat(32) }) }),
  );
});

function sessionResponse() {
  return new Response(
    JSON.stringify({
      data: {
        access_token: "signed-access-token",
        identity: { tenant_id: "tenant-id", actor_id: "actor-id", permissions: [] },
      },
    }),
    { status: 201, headers: { "content-type": "application/json" } },
  );
}
