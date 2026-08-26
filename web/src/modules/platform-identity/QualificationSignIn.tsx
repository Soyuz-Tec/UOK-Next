import { useState, type FormEvent } from "react";

import { signInWithAccessCode, signInWithPassword, type Session } from "./sessionApi";

type Props = { onAuthenticated: (session: Session) => void };
type SignInMode = "user" | "bootstrap";

export function QualificationSignIn({ onAuthenticated }: Props) {
  const [mode, setMode] = useState<SignInMode>("user");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [accessCode, setAccessCode] = useState("");
  const [error, setError] = useState<string>();
  const [submitting, setSubmitting] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setError(undefined);

    try {
      const session =
        mode === "user"
          ? await signInWithPassword(username, password)
          : await signInWithAccessCode(accessCode);
      onAuthenticated(session);
      setPassword("");
      setAccessCode("");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Authentication failed");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <section className="signin-panel" aria-labelledby="signin-title">
      <div>
        <span className="eyebrow">Gate 3 workspace</span>
        <h1 id="signin-title">Continue with your own attributable account.</h1>
        <p>
          Regular users receive only their tenant and role permissions. The protected local access
          code remains available to administrators for user setup.
        </p>
      </div>
      <div className="signin-card">
        <div className="signin-switch" aria-label="Sign-in method">
          <button
            type="button"
            className={mode === "user" ? "signin-switch--active" : "button-secondary"}
            aria-pressed={mode === "user"}
            onClick={() => setMode("user")}
          >
            Username
          </button>
          <button
            type="button"
            className={mode === "bootstrap" ? "signin-switch--active" : "button-secondary"}
            aria-pressed={mode === "bootstrap"}
            onClick={() => setMode("bootstrap")}
          >
            Administrator access
          </button>
        </div>
        <form onSubmit={(event) => void submit(event)}>
          {mode === "user" ? (
            <>
              <label htmlFor="username">Username</label>
              <input
                id="username"
                name="username"
                autoComplete="username"
                required
                minLength={3}
                maxLength={64}
                value={username}
                onChange={(event) => setUsername(event.currentTarget.value)}
              />
              <label htmlFor="password">Password</label>
              <input
                id="password"
                name="password"
                type="password"
                autoComplete="current-password"
                required
                maxLength={128}
                value={password}
                onChange={(event) => setPassword(event.currentTarget.value)}
              />
            </>
          ) : (
            <>
              <label htmlFor="access-code">Local access code</label>
              <input
                id="access-code"
                name="access-code"
                type="password"
                autoComplete="current-password"
                required
                minLength={32}
                maxLength={128}
                value={accessCode}
                onChange={(event) => setAccessCode(event.currentTarget.value)}
              />
            </>
          )}
          {error === undefined ? null : <p className="form-error">{error}</p>}
          <button type="submit" disabled={submitting}>
            {submitting ? "Authenticating…" : "Enter workspace"}
          </button>
        </form>
      </div>
    </section>
  );
}
