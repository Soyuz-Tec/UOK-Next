import { useState, type FormEvent } from "react";

import { changePassword, type Session } from "./sessionApi";

type Props = { session: Session; onCompleted: () => void };

export function PasswordActivation({ session, onCompleted }: Props) {
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [error, setError] = useState<string>();
  const [submitting, setSubmitting] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setError(undefined);

    try {
      await changePassword(session, currentPassword, newPassword, confirmation);
      onCompleted();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Password change failed");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <section className="signin-panel" aria-labelledby="activation-title">
      <div>
        <span className="eyebrow">Account activation</span>
        <h1 id="activation-title">Make this account yours.</h1>
        <p>
          Replace the temporary password before entering the workspace. Every earlier session is
          revoked when the change succeeds.
        </p>
      </div>
      <form onSubmit={(event) => void submit(event)}>
        <p>
          Signed in as <strong>{session.identity.username}</strong>
        </p>
        <label htmlFor="current-password">Temporary password</label>
        <input
          id="current-password"
          type="password"
          autoComplete="current-password"
          required
          value={currentPassword}
          onChange={(event) => setCurrentPassword(event.currentTarget.value)}
        />
        <label htmlFor="new-password">New passphrase</label>
        <input
          id="new-password"
          type="password"
          autoComplete="new-password"
          required
          minLength={15}
          maxLength={128}
          value={newPassword}
          onChange={(event) => setNewPassword(event.currentTarget.value)}
        />
        <small>Use 15–128 characters. Spaces and password-manager paste are supported.</small>
        <label htmlFor="new-password-confirmation">Confirm new passphrase</label>
        <input
          id="new-password-confirmation"
          type="password"
          autoComplete="new-password"
          required
          minLength={15}
          maxLength={128}
          value={confirmation}
          onChange={(event) => setConfirmation(event.currentTarget.value)}
        />
        {error === undefined ? null : <p className="form-error">{error}</p>}
        <button disabled={submitting || newPassword !== confirmation}>
          {submitting ? "Activating…" : "Activate and sign in again"}
        </button>
      </form>
    </section>
  );
}
