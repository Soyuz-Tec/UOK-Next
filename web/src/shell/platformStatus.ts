export type PlatformStatus =
  | { phase: "checking"; label: string; detail: string }
  | { phase: "ready"; label: string; detail: string }
  | { phase: "unavailable"; label: string; detail: string };

export const checkingStatus: PlatformStatus = {
  phase: "checking",
  label: "Checking kernel",
  detail: "Confirming the release and its governed data dependency.",
};

const unavailableStatus: PlatformStatus = {
  phase: "unavailable",
  label: "Kernel unavailable",
  detail: "The readiness contract did not respond. Business actions remain unavailable.",
};

export async function readPlatformStatus(signal: AbortSignal): Promise<PlatformStatus> {
  try {
    const response = await fetch("/api/v1/health/ready", {
      credentials: "same-origin",
      headers: { Accept: "application/json" },
      signal,
    });
    const body: unknown = await response.json();

    if (!response.ok || !isReadyResponse(body)) {
      return unavailableStatus;
    }

    return {
      phase: "ready",
      label: "Kernel ready",
      detail: "The release and governed PostgreSQL dependency passed readiness checks.",
    };
  } catch {
    return unavailableStatus;
  }
}

function isReadyResponse(value: unknown): value is { status: "ready" } {
  return (
    typeof value === "object" && value !== null && "status" in value && value.status === "ready"
  );
}
