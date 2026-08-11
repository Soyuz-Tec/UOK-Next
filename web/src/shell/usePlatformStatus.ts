import { useEffect, useState } from "react";

import { checkingStatus, readPlatformStatus, type PlatformStatus } from "./platformStatus";

export function usePlatformStatus(): PlatformStatus {
  const [status, setStatus] = useState<PlatformStatus>(checkingStatus);

  useEffect(() => {
    const controller = new AbortController();

    void readPlatformStatus(controller.signal).then((nextStatus) => {
      if (!controller.signal.aborted) {
        setStatus(nextStatus);
      }
    });

    return () => {
      controller.abort();
    };
  }, []);

  return status;
}
