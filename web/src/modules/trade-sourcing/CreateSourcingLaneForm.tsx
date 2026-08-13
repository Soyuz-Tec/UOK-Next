import type { FormEvent } from "react";

import type { Party } from "../master-parties/partyApi";
import type { Location, Product } from "./referenceApi";
import type { SourcingLaneInput } from "./sourcingApi";

type Props = {
  busy: boolean;
  form: SourcingLaneInput;
  locations: Location[];
  parties: Party[];
  products: Product[];
  ready: boolean;
  onChange: (form: SourcingLaneInput) => void;
  onSubmit: (event: FormEvent<HTMLFormElement>) => void;
};

export function CreateSourcingLaneForm(props: Props) {
  const { busy, form, locations, parties, products, ready, onChange, onSubmit } = props;

  return (
    <form className="command-form" onSubmit={onSubmit}>
      <span className="eyebrow">New trade authority</span>
      <h2>Create sourcing lane</h2>
      {!ready ? (
        <p className="setup-note">
          An approved party, one product, and two locations are required.
        </p>
      ) : null}
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
        Lane name
        <input
          required
          minLength={2}
          maxLength={200}
          value={form.name}
          onChange={(event) => onChange({ ...form, name: event.currentTarget.value })}
        />
      </label>
      <label>
        Approved supplier
        <select
          required
          value={form.supplier_party_id}
          onChange={(event) => onChange({ ...form, supplier_party_id: event.currentTarget.value })}
        >
          <option value="">Select supplier</option>
          {parties.map((party) => (
            <option key={party.id} value={party.id}>
              {party.legal_name}
            </option>
          ))}
        </select>
      </label>
      <label>
        Product
        <select
          required
          value={form.product_id}
          onChange={(event) => onChange({ ...form, product_id: event.currentTarget.value })}
        >
          <option value="">Select product</option>
          {products.map((product) => (
            <option key={product.id} value={product.id}>
              {product.name} · {product.base_unit_code}
            </option>
          ))}
        </select>
      </label>
      <div className="form-row">
        <LocationSelect
          label="Origin"
          value={form.origin_location_id}
          locations={locations}
          onChange={(value) => onChange({ ...form, origin_location_id: value })}
        />
        <LocationSelect
          label="Destination"
          value={form.destination_location_id}
          locations={locations}
          onChange={(value) => onChange({ ...form, destination_location_id: value })}
        />
      </div>
      <button disabled={busy || !ready}>Create governed lane</button>
    </form>
  );
}

type LocationSelectProps = {
  label: string;
  value: string;
  locations: Location[];
  onChange: (value: string) => void;
};

function LocationSelect({ label, value, locations, onChange }: LocationSelectProps) {
  return (
    <label>
      {label}
      <select required value={value} onChange={(event) => onChange(event.currentTarget.value)}>
        <option value="">Select {label.toLowerCase()}</option>
        {locations.map((location) => (
          <option key={location.id} value={location.id}>
            {location.name}
          </option>
        ))}
      </select>
    </label>
  );
}
