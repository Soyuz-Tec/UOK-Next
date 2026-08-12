import { useState, type FormEvent } from "react";

import { signIn, type Session } from "./sessionApi";

type Props = { onAuthenticated: (session: Session) => void };

export function QualificationSignIn({ onAuthenticated }: Props) {
  const [accessCode, setAccessCode] = useState("");
  const [error, setError] = useState<string>();
  const [submitting, setSubmitting] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setError(undefined);

    try {
      onAuthenticated(await signIn(accessCode));
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
        <h1 id="signin-title">Open the governed onboarding workspace.</h1>
        <p>
          This local qualification sign-in issues a short-lived tenant-bound access token. It is
          disabled outside the isolated qualification profile.
        </p>
      </div>
      <form onSubmit={(event) => void submit(event)}>
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
        {error === undefined ? null : <p className="form-error">{error}</p>}
        <button type="submit" disabled={submitting}>
          {submitting ? "Authenticating…" : "Enter workspace"}
        </button>
      </form>
    </section>
  );
}
