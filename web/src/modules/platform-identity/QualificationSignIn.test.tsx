import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { expect, test, vi } from "vitest";

import { QualificationSignIn } from "./QualificationSignIn";

test("authenticates with only the local access code and returns the server identity", async () => {
  const user = userEvent.setup();
  const authenticated = vi.fn();

  vi.spyOn(globalThis, "fetch").mockResolvedValue(
    new Response(
      JSON.stringify({
        data: {
          access_token: "signed-access-token",
          identity: { tenant_id: "tenant-id", actor_id: "actor-id", permissions: [] },
        },
      }),
      { status: 201, headers: { "content-type": "application/json" } },
    ),
  );

  render(<QualificationSignIn onAuthenticated={authenticated} />);
  await user.type(screen.getByLabelText("Local access code"), "x".repeat(32));
  await user.click(screen.getByRole("button", { name: "Enter workspace" }));

  expect(fetch).toHaveBeenCalledWith(
    "/api/v1/session",
    expect.objectContaining({ body: JSON.stringify({ access_code: "x".repeat(32) }) }),
  );
  expect(authenticated).toHaveBeenCalledWith(
    expect.objectContaining({
      accessToken: "signed-access-token",
      identity: expect.objectContaining({ tenant_id: "tenant-id" }),
    }),
  );
});
