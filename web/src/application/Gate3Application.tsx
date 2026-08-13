import { useEffect, useState } from "react";

import { PartyOnboardingWorkspace } from "../modules/master-parties/PartyOnboardingWorkspace";
import { QualificationSignIn } from "../modules/platform-identity/QualificationSignIn";
import { verifySession, type Session } from "../modules/platform-identity/sessionApi";
import { ProductSourcingWorkspace } from "../modules/trade-sourcing/ProductSourcingWorkspace";
import { ProcurementWorkspace } from "../modules/trade-sourcing/ProcurementWorkspace";

const storageKey = "uok-next-local-session-v1";

function storedSession(): Session | undefined {
  try {
    const value = sessionStorage.getItem(storageKey);
    return value === null ? undefined : (JSON.parse(value) as Session);
  } catch {
    return undefined;
  }
}

export function Gate3Application() {
  const [session, setSession] = useState<Session | undefined>(storedSession);
  const [surface, setSurface] = useState(window.location.hash);

  useEffect(() => {
    const updateSurface = () => setSurface(window.location.hash);
    window.addEventListener("hashchange", updateSurface);
    return () => window.removeEventListener("hashchange", updateSurface);
  }, []);

  useEffect(() => {
    if (session === undefined) return;
    void verifySession(session).catch(() => {
      sessionStorage.removeItem(storageKey);
      setSession(undefined);
    });
  }, [session]);

  function authenticated(nextSession: Session) {
    sessionStorage.setItem(storageKey, JSON.stringify(nextSession));
    setSession(nextSession);
  }

  function signOut() {
    sessionStorage.removeItem(storageKey);
    setSession(undefined);
  }

  if (session === undefined) {
    return <QualificationSignIn onAuthenticated={authenticated} />;
  }

  if (surface === "#rfq-comparison") {
    return (
      <ProcurementWorkspace
        token={session.accessToken}
        tenantId={session.identity.tenant_id}
        onSignOut={signOut}
      />
    );
  }

  return surface === "#product-sourcing" ? (
    <ProductSourcingWorkspace
      token={session.accessToken}
      tenantId={session.identity.tenant_id}
      onSignOut={signOut}
    />
  ) : (
    <PartyOnboardingWorkspace
      token={session.accessToken}
      tenantId={session.identity.tenant_id}
      onSignOut={signOut}
    />
  );
}
