import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, expect, test, vi } from "vitest";

import { Gate3Application } from "./Gate3Application";
import {
  revokeSession,
  verifySession,
  type Session,
} from "../modules/platform-identity/sessionApi";

vi.mock("../modules/platform-identity/sessionApi", async (importOriginal) => {
  const original = await importOriginal<typeof import("../modules/platform-identity/sessionApi")>();

  return {
    ...original,
    verifySession: vi.fn(),
    revokeSession: vi.fn(),
  };
});

vi.mock("../modules/master-parties/PartyOnboardingWorkspace", () => ({
  PartyOnboardingWorkspace: ({ onSignOut }: { onSignOut: () => void }) => (
    <button type="button" onClick={onSignOut}>
      Sign out
    </button>
  ),
}));

const storageKey = "uok-next-local-session-v1";

const session: Session = {
  accessToken: "uokba1.session.secret",
  identity: {
    tenant_id: "11111111-1111-4111-8111-111111111111",
    actor_id: "22222222-2222-4222-8222-222222222222",
    permissions: ["identity:users:manage"],
  },
  passwordChangeRequired: false,
};

beforeEach(() => {
  window.location.hash = "#party-onboarding";
  sessionStorage.setItem(storageKey, JSON.stringify(session));
  vi.mocked(verifySession).mockResolvedValue(session);
});

test("keeps the browser session when server revocation is not confirmed", async () => {
  vi.mocked(revokeSession).mockRejectedValue(new Error("not confirmed"));
  render(<Gate3Application />);

  await userEvent.click(screen.getByRole("button", { name: "Sign out" }));

  expect(await screen.findByRole("alert")).toHaveTextContent("session remains active");
  expect(sessionStorage.getItem(storageKey)).not.toBeNull();
  expect(screen.getByRole("button", { name: "Sign out" })).toBeInTheDocument();
});

test("clears the browser session after confirmed server revocation", async () => {
  vi.mocked(revokeSession).mockResolvedValue();
  render(<Gate3Application />);

  await userEvent.click(screen.getByRole("button", { name: "Sign out" }));

  await waitFor(() => expect(sessionStorage.getItem(storageKey)).toBeNull());
  expect(
    screen.getByRole("heading", { name: "Continue with your own attributable account." }),
  ).toBeInTheDocument();
});
