import { useEffect, useState } from "react";

import { PartyOnboardingWorkspace } from "../modules/master-parties/PartyOnboardingWorkspace";
import { OperationalReportWorkspace } from "../modules/intelligence-bi/OperationalReportWorkspace";
import { QualificationSignIn } from "../modules/platform-identity/QualificationSignIn";
import { PasswordActivation } from "../modules/platform-identity/PasswordActivation";
import { UserAccessWorkspace } from "../modules/platform-identity/UserAccessWorkspace";
import {
  revokeSession,
  verifySession,
  type Session,
} from "../modules/platform-identity/sessionApi";
import { PurchaseCommitmentWorkspace } from "../modules/trade-contracts/PurchaseCommitmentWorkspace";
import { ShipmentReadinessWorkspace } from "../modules/trade-shipments/ShipmentReadinessWorkspace";
import { ProductSourcingWorkspace } from "../modules/trade-sourcing/ProductSourcingWorkspace";
import { ProcurementWorkspace } from "../modules/trade-sourcing/ProcurementWorkspace";

const storageKey = "uok-next-local-session-v1";

function storedSession(): Session | undefined {
  try {
    const value = sessionStorage.getItem(storageKey);
    if (value === null) return undefined;
    const parsed = JSON.parse(value) as Session;
    return { ...parsed, passwordChangeRequired: parsed.passwordChangeRequired ?? false };
  } catch {
    return undefined;
  }
}

export function Gate3Application() {
  const [session, setSession] = useState<Session | undefined>(storedSession);
  const [surface, setSurface] = useState(window.location.hash);
  const [signOutError, setSignOutError] = useState<string | undefined>();

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
    setSignOutError(undefined);
    setSession(nextSession);
  }

  function clearSession() {
    sessionStorage.removeItem(storageKey);
    setSession(undefined);
  }

  async function signOut() {
    if (session === undefined) return;

    setSignOutError(undefined);

    try {
      await revokeSession(session);
      clearSession();
    } catch {
      setSignOutError("Sign out was not confirmed. Your session remains active; try again.");
    }
  }

  if (session === undefined) {
    return <QualificationSignIn onAuthenticated={authenticated} />;
  }

  if (session.passwordChangeRequired) {
    return <PasswordActivation session={session} onCompleted={clearSession} />;
  }

  let workspace;

  if (surface === "#users-access") {
    workspace = (
      <UserAccessWorkspace
        token={session.accessToken}
        tenantId={session.identity.tenant_id}
        onSignOut={signOut}
      />
    );
  } else if (surface === "#rfq-comparison") {
    workspace = (
      <ProcurementWorkspace
        token={session.accessToken}
        tenantId={session.identity.tenant_id}
        onSignOut={signOut}
      />
    );
  } else if (surface === "#commitment-proposal") {
    workspace = (
      <PurchaseCommitmentWorkspace
        token={session.accessToken}
        tenantId={session.identity.tenant_id}
        onSignOut={signOut}
      />
    );
  } else if (surface === "#shipment-readiness") {
    workspace = (
      <ShipmentReadinessWorkspace
        token={session.accessToken}
        tenantId={session.identity.tenant_id}
        onSignOut={signOut}
      />
    );
  } else if (surface === "#operational-report") {
    workspace = (
      <OperationalReportWorkspace
        token={session.accessToken}
        tenantId={session.identity.tenant_id}
        onSignOut={signOut}
      />
    );
  } else if (surface === "#product-sourcing") {
    workspace = (
      <ProductSourcingWorkspace
        token={session.accessToken}
        tenantId={session.identity.tenant_id}
        onSignOut={signOut}
      />
    );
  } else {
    workspace = (
      <PartyOnboardingWorkspace
        token={session.accessToken}
        tenantId={session.identity.tenant_id}
        permissions={session.identity.permissions}
        onSignOut={signOut}
      />
    );
  }

  return (
    <>
      {signOutError !== undefined && (
        <div className="workspace-error" role="alert">
          {signOutError}
        </div>
      )}
      {workspace}
    </>
  );
}
