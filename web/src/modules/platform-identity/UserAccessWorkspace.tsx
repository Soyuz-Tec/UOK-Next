import { useCallback, useEffect, useState, type FormEvent } from "react";

import {
  createLocalUser,
  listAccessProfiles,
  listLocalUsers,
  type AccessProfile,
  type LocalUser,
} from "./userAccessApi";

type Props = { token: string; tenantId: string; onSignOut: () => void };

const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789-_";

function generatedPassword(): string {
  const values = crypto.getRandomValues(new Uint8Array(24));
  return Array.from(values, (value) => alphabet[value % alphabet.length]).join("");
}

export function UserAccessWorkspace({ token, tenantId, onSignOut }: Props) {
  const [users, setUsers] = useState<LocalUser[]>([]);
  const [profiles, setProfiles] = useState<AccessProfile[]>([]);
  const [username, setUsername] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [accessProfile, setAccessProfile] = useState("entity_onboarding_operator");
  const [temporaryPassword, setTemporaryPassword] = useState(generatedPassword);
  const [showPassword, setShowPassword] = useState(false);
  const [createdUsername, setCreatedUsername] = useState<string>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  const refresh = useCallback(async () => {
    const [nextUsers, nextProfiles] = await Promise.all([
      listLocalUsers(token),
      listAccessProfiles(token),
    ]);
    setUsers(nextUsers);
    setProfiles(nextProfiles);
  }, [token]);

  useEffect(() => {
    let active = true;

    void Promise.all([listLocalUsers(token), listAccessProfiles(token)])
      .then(([nextUsers, nextProfiles]) => {
        if (!active) return;
        setUsers(nextUsers);
        setProfiles(nextProfiles);
      })
      .catch((reason: unknown) => {
        if (active) {
          setError(reason instanceof Error ? reason.message : "User access could not be loaded");
        }
      });

    return () => {
      active = false;
    };
  }, [token]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError(undefined);
    setCreatedUsername(undefined);

    try {
      const created = await createLocalUser(token, {
        username,
        display_name: displayName,
        access_profile: accessProfile,
        temporary_password: temporaryPassword,
        reason: "Provision an attributable entity onboarding user",
      });
      setCreatedUsername(created.username);
      setUsername("");
      setDisplayName("");
      await refresh();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "User creation was rejected");
    } finally {
      setBusy(false);
    }
  }

  function prepareAnother() {
    setCreatedUsername(undefined);
    setTemporaryPassword(generatedPassword());
    setShowPassword(false);
  }

  return (
    <section className="user-access-workspace" id="users-access" aria-labelledby="users-title">
      <header className="workspace-heading">
        <div>
          <span className="eyebrow">Platform identity · local qualification</span>
          <h1 id="users-title">Give every operator their own attributable access.</h1>
          <p>
            Tenant {tenantId.slice(0, 8)}… · passwords are never stored or returned in plaintext.
          </p>
        </div>
        <button className="button-secondary" type="button" onClick={onSignOut}>
          Sign out
        </button>
      </header>

      {error === undefined ? null : <div className="workspace-error">{error}</div>}

      <div className="user-access-grid">
        <section className="party-list" aria-labelledby="user-directory-title">
          <div className="panel-heading">
            <div>
              <span className="eyebrow">Directory</span>
              <h2 id="user-directory-title">Local users</h2>
            </div>
            <span className="count-badge">{users.length}</span>
          </div>
          {users.length === 0 ? <p className="empty-state">No regular users yet.</p> : null}
          {users.map((user) => (
            <div className="local-user-row" key={user.id}>
              <span>
                <strong>{user.display_name}</strong>
                <small>@{user.username}</small>
              </span>
              <span>
                <small>{user.access_profile.replaceAll("_", " ")}</small>
                <span className={`status status--${user.status}`}>{user.status}</span>
              </span>
            </div>
          ))}
        </section>

        <section className="work-panel" aria-labelledby="create-user-title">
          {createdUsername === undefined ? (
            <form
              className="command-form command-form--create"
              onSubmit={(event) => void submit(event)}
            >
              <span className="eyebrow">One controlled handoff</span>
              <h2 id="create-user-title">Create an onboarding user</h2>
              <div className="form-row">
                <label>
                  Username
                  <input
                    autoComplete="off"
                    required
                    minLength={3}
                    maxLength={64}
                    pattern="[a-z0-9][a-z0-9._-]{2,63}"
                    value={username}
                    onChange={(event) => setUsername(event.currentTarget.value.toLowerCase())}
                  />
                </label>
                <label>
                  Display name
                  <input
                    autoComplete="name"
                    required
                    minLength={2}
                    maxLength={120}
                    value={displayName}
                    onChange={(event) => setDisplayName(event.currentTarget.value)}
                  />
                </label>
              </div>
              <label>
                Access profile
                <select
                  value={accessProfile}
                  onChange={(event) => setAccessProfile(event.currentTarget.value)}
                >
                  {(profiles.length === 0
                    ? [
                        {
                          key: "entity_onboarding_operator",
                          label: "Entity onboarding operator",
                        },
                      ]
                    : profiles
                  ).map((profile) => (
                    <option key={profile.key} value={profile.key}>
                      {profile.label}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Temporary password
                <input
                  type={showPassword ? "text" : "password"}
                  autoComplete="new-password"
                  required
                  minLength={15}
                  maxLength={128}
                  value={temporaryPassword}
                  onChange={(event) => setTemporaryPassword(event.currentTarget.value)}
                />
              </label>
              <div className="temporary-password-actions">
                <button
                  className="button-secondary"
                  type="button"
                  onClick={() => setTemporaryPassword(generatedPassword())}
                >
                  Generate another
                </button>
                <button
                  className="button-secondary"
                  type="button"
                  aria-pressed={showPassword}
                  onClick={() => setShowPassword((visible) => !visible)}
                >
                  {showPassword ? "Hide password" : "Show password"}
                </button>
              </div>
              <p className="form-guidance">
                Share this temporary value once. The user must replace it before accessing any
                entity records.
              </p>
              <button disabled={busy}>{busy ? "Creating…" : "Create user"}</button>
            </form>
          ) : (
            <div className="activation-handoff" role="status">
              <span className="eyebrow">User created</span>
              <h2>Hand access to @{createdUsername}</h2>
              <p>Copy the temporary password now. The application retained only its verifier.</p>
              <output aria-label="Temporary password">{temporaryPassword}</output>
              <button type="button" onClick={prepareAnother}>
                Create another user
              </button>
            </div>
          )}
        </section>
      </div>
    </section>
  );
}
