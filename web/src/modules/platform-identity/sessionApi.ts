export type SessionIdentity = {
  tenant_id: string;
  actor_id: string;
  permissions: string[];
};

export type Session = {
  accessToken: string;
  identity: SessionIdentity;
};

type ApiEnvelope<T> = { data?: T; error?: { code: string; message: string } };

export async function signIn(accessCode: string): Promise<Session> {
  const response = await fetch("/api/v1/session", {
    method: "POST",
    credentials: "same-origin",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ access_code: accessCode }),
  });
  const envelope = (await response.json()) as ApiEnvelope<{
    access_token: string;
    identity: SessionIdentity;
  }>;

  if (!response.ok || envelope.data === undefined) {
    throw new Error(envelope.error?.message ?? "Authentication failed");
  }

  return { accessToken: envelope.data.access_token, identity: envelope.data.identity };
}

export async function verifySession(session: Session): Promise<Session> {
  const response = await fetch("/api/v1/session", {
    credentials: "same-origin",
    headers: { authorization: `Bearer ${session.accessToken}` },
  });

  if (!response.ok) {
    throw new Error("Session expired");
  }

  return session;
}
