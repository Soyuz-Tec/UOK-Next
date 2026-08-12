import { useState, type FormEvent } from "react";

import type { LocationInput, ProductInput } from "./referenceApi";

type Props = {
  busy: boolean;
  onProduct: (input: ProductInput) => Promise<void>;
  onLocation: (input: LocationInput) => Promise<void>;
};

const emptyProduct: ProductInput = {
  stable_identifier: "",
  name: "",
  product_kind: "commodity",
  base_unit_code: "MT",
  reason: "Establish governed product authority",
};

const emptyLocation: LocationInput = {
  stable_identifier: "",
  name: "",
  country_code: "",
  location_kind: "port",
  reason: "Establish governed route location",
};

export function ReferenceSetupPanel({ busy, onProduct, onLocation }: Props) {
  const [product, setProduct] = useState(emptyProduct);
  const [location, setLocation] = useState(emptyLocation);

  async function submitProduct(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    await onProduct(product);
    setProduct(emptyProduct);
  }

  async function submitLocation(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    await onLocation(location);
    setLocation(emptyLocation);
  }

  return (
    <div className="reference-grid">
      <form className="command-form compact-form" onSubmit={(event) => void submitProduct(event)}>
        <span className="eyebrow">Product authority</span>
        <h2>Create product</h2>
        <label>
          Stable identifier
          <input
            required
            minLength={3}
            maxLength={100}
            value={product.stable_identifier}
            onChange={(event) =>
              setProduct({ ...product, stable_identifier: event.currentTarget.value })
            }
          />
        </label>
        <label>
          Name
          <input
            required
            minLength={2}
            maxLength={200}
            value={product.name}
            onChange={(event) => setProduct({ ...product, name: event.currentTarget.value })}
          />
        </label>
        <div className="form-row">
          <label>
            Kind
            <select
              value={product.product_kind}
              onChange={(event) =>
                setProduct({
                  ...product,
                  product_kind: event.currentTarget.value as ProductInput["product_kind"],
                })
              }
            >
              <option value="commodity">Commodity</option>
              <option value="packaging">Packaging</option>
              <option value="service">Service</option>
            </select>
          </label>
          <label>
            Unit
            <input
              required
              maxLength={16}
              value={product.base_unit_code}
              onChange={(event) =>
                setProduct({ ...product, base_unit_code: event.currentTarget.value.toUpperCase() })
              }
            />
          </label>
        </div>
        <button disabled={busy}>Create product</button>
      </form>

      <form className="command-form compact-form" onSubmit={(event) => void submitLocation(event)}>
        <span className="eyebrow">Location authority</span>
        <h2>Create route location</h2>
        <label>
          Stable identifier
          <input
            required
            minLength={3}
            maxLength={100}
            value={location.stable_identifier}
            onChange={(event) =>
              setLocation({ ...location, stable_identifier: event.currentTarget.value })
            }
          />
        </label>
        <label>
          Name
          <input
            required
            minLength={2}
            maxLength={200}
            value={location.name}
            onChange={(event) => setLocation({ ...location, name: event.currentTarget.value })}
          />
        </label>
        <div className="form-row">
          <label>
            Country
            <input
              required
              minLength={2}
              maxLength={2}
              value={location.country_code}
              onChange={(event) =>
                setLocation({ ...location, country_code: event.currentTarget.value.toUpperCase() })
              }
            />
          </label>
          <label>
            Kind
            <select
              value={location.location_kind}
              onChange={(event) =>
                setLocation({
                  ...location,
                  location_kind: event.currentTarget.value as LocationInput["location_kind"],
                })
              }
            >
              <option value="port">Port</option>
              <option value="facility">Facility</option>
              <option value="locality">Locality</option>
              <option value="region">Region</option>
              <option value="country">Country</option>
            </select>
          </label>
        </div>
        <button disabled={busy}>Create location</button>
      </form>
    </div>
  );
}
