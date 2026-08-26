export type SessionIdentity = {
  tenant_id: string;
  actor_id: string;
  username?: string;
  display_name?: string;
  access_profile?: string;
  password_change_required?: boolean;
  permissions: string[];
};

export type Session = {
  accessToken: string;
  identity: SessionIdentity;
  passwordChangeRequired: boolean;
};

type ApiEnvelope<T> = { data?: T; error?: { code: string; message: string } };

async function createSession(body: Record<string, string>): Promise<Session> {
  const response = await fetch("/api/v1/session", {
    method: "POST",
    credentials: "same-origin",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const envelope = (await response.json()) as ApiEnvelope<{
    access_token: string;
    password_change_required?: boolean;
    identity: SessionIdentity;
  }>;

  if (!response.ok || envelope.data === undefined) {
    throw new Error(envelope.error?.message ?? "Authentication failed");
  }

  return {
    accessToken: envelope.data.access_token,
    identity: envelope.data.identity,
    passwordChangeRequired:
      envelope.data.password_change_required ??
      envelope.data.identity.password_change_required ??
      false,
  };
}

export function signInWithAccessCode(accessCode: string): Promise<Session> {
  return createSession({ access_code: accessCode });
}

export function signInWithPassword(username: string, password: string): Promise<Session> {
  return createSession({ username, password });
}

export async function verifySession(session: Session): Promise<Session> {
  const response = await fetch("/api/v1/session", {
    credentials: "same-origin",
    headers: { authorization: `Bearer ${session.accessToken}` },
  });

  const envelope = (await response.json()) as ApiEnvelope<SessionIdentity>;

  if (!response.ok || envelope.data === undefined) {
    throw new Error("Session expired");
  }

  return {
    ...session,
    identity: envelope.data,
    passwordChangeRequired: envelope.data.password_change_required ?? false,
  };
}

export async function changePassword(
  session: Session,
  currentPassword: string,
  newPassword: string,
  confirmation: string,
): Promise<void> {
  const response = await fetch("/api/v1/session/password", {
    method: "POST",
    credentials: "same-origin",
    headers: {
      authorization: `Bearer ${session.accessToken}`,
      "content-type": "application/json",
      "idempotency-key": crypto.randomUUID(),
    },
    body: JSON.stringify({
      current_password: currentPassword,
      new_password: newPassword,
      new_password_confirmation: confirmation,
    }),
  });

  if (!response.ok) {
    const envelope = (await response.json()) as ApiEnvelope<never>;
    throw new Error(envelope.error?.message ?? "Password change failed");
  }
}

export async function revokeSession(session: Session): Promise<void> {
  const response = await fetch("/api/v1/session", {
    method: "DELETE",
    credentials: "same-origin",
    headers: { authorization: `Bearer ${session.accessToken}` },
  });

  const envelope = (await response.json()) as ApiEnvelope<{ revoked: boolean }>;

  if (!response.ok || envelope.data?.revoked !== true) {
    throw new Error(envelope.error?.message ?? "Sign out was not confirmed");
  }
}
