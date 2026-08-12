import type { FormEvent } from "react";
import type { PartyForm } from "./partyForm";

type Props = {
  form: PartyForm;
  busy: boolean;
  onChange: (form: PartyForm) => void;
  onSubmit: (event: FormEvent<HTMLFormElement>) => void;
};

export function CreatePartyForm({ form, busy, onChange, onSubmit }: Props) {
  return (
    <form className="command-form command-form--create" onSubmit={onSubmit}>
      <span className="eyebrow">New governed record</span>
      <h2>Create party draft</h2>
      <label>
        Stable identifier
        <input
          required
          minLength={3}
          maxLength={100}
          value={form.stable_identifier}
          onChange={(event) => onChange({ ...form, stable_identifier: event.currentTarget.value })}
        />
      </label>
      <label>
        Legal name
        <input
          required
          minLength={2}
          maxLength={200}
          value={form.legal_name}
          onChange={(event) => onChange({ ...form, legal_name: event.currentTarget.value })}
        />
      </label>
      <div className="form-row">
        <label>
          Country code
          <input
            required
            minLength={2}
            maxLength={2}
            value={form.country_code}
            onChange={(event) =>
              onChange({ ...form, country_code: event.currentTarget.value.toUpperCase() })
            }
          />
        </label>
        <label>
          Party kind
          <select
            value={form.party_kind}
            onChange={(event) =>
              onChange({ ...form, party_kind: event.currentTarget.value as typeof form.party_kind })
            }
          >
            <option value="organization">Organization</option>
            <option value="individual">Individual</option>
          </select>
        </label>
      </div>
      <label>
        Reason
        <textarea
          required
          minLength={3}
          maxLength={500}
          value={form.reason}
          onChange={(event) => onChange({ ...form, reason: event.currentTarget.value })}
        />
      </label>
      <button disabled={busy}>{busy ? "Creating…" : "Create governed draft"}</button>
    </form>
  );
}
