import { render, screen } from "@testing-library/react";
import { expect, test, vi } from "vitest";

import { AppShell } from "./AppShell";

test("renders a truthful module-neutral foundation shell", async () => {
  vi.spyOn(globalThis, "fetch").mockResolvedValue(
    new Response(JSON.stringify({ status: "ready" }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );

  render(<AppShell />);

  expect(
    screen.getByRole("heading", { name: "One trusted path from decision to evidence." }),
  ).toBeVisible();
  expect(screen.getByText("No production claim")).toBeVisible();
  expect(screen.getByText("Gate 1")).toBeVisible();
  expect(screen.getByText("Final qualification")).toBeVisible();
  expect(screen.getAllByText("Qualification")).toHaveLength(2);
  expect(screen.getAllByText("Presentation only")).toHaveLength(1);
  expect(await screen.findAllByText("Kernel ready")).toHaveLength(2);
  expect(screen.queryByRole("button")).not.toBeInTheDocument();
});
