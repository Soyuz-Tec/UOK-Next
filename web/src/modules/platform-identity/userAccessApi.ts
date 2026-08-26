import { authorizedRequest } from "../../shared/authorizedApi";

export type LocalUser = {
  id: string;
  username: string;
  display_name: string;
  access_profile: string;
  status: "pending_activation" | "active" | "suspended";
  must_change_password: boolean;
  lock_version: number;
};

export type AccessProfile = {
  key: string;
  label: string;
  permissions: string[];
};

export type CreateLocalUserInput = {
  username: string;
  display_name: string;
  access_profile: string;
  temporary_password: string;
  reason: string;
};

export function listLocalUsers(token: string): Promise<LocalUser[]> {
  return authorizedRequest<LocalUser[]>("/api/v1/identity/users?limit=100", token);
}

export function listAccessProfiles(token: string): Promise<AccessProfile[]> {
  return authorizedRequest<AccessProfile[]>("/api/v1/identity/access-profiles", token);
}

export function createLocalUser(token: string, input: CreateLocalUserInput): Promise<LocalUser> {
  return authorizedRequest<LocalUser>("/api/v1/identity/users", token, {
    method: "POST",
    headers: { "content-type": "application/json", "idempotency-key": crypto.randomUUID() },
    body: JSON.stringify(input),
  });
}
