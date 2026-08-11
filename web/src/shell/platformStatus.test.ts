import { describe, expect, test, vi } from "vitest";

import { readPlatformStatus } from "./platformStatus";

describe("readPlatformStatus", () => {
  test("accepts only the explicit ready contract", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ status: "ready" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );

    const result = await readPlatformStatus(new AbortController().signal);

    expect(result.phase).toBe("ready");
    expect(fetch).toHaveBeenCalledWith(
      "/api/v1/health/ready",
      expect.objectContaining({ credentials: "same-origin" }),
    );
  });

  test("fails closed when an untrusted response does not match", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ status: "ready", trusted: false }), { status: 503 }),
    );

    await expect(readPlatformStatus(new AbortController().signal)).resolves.toMatchObject({
      phase: "unavailable",
    });
  });
});
