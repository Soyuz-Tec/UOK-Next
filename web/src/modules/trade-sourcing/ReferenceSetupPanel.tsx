import { useMemo, useState, type FormEvent } from "react";

import type {
  Location,
  LocationInput,
  MajorSeaport,
  MajorSeaportCountry,
  ProductInput,
} from "./referenceApi";
import { LocationPreview, ManualLocationFields, SeaportFields } from "./RouteLocationFields";

type Props = {
  busy: boolean;
  locations: Location[];
  seaportCatalogBusy: boolean;
  seaportCatalogError: string | undefined;
  seaportCatalogVersion: string | undefined;
  seaportCountries: MajorSeaportCountry[];
  seaports: MajorSeaport[];
  onProduct: (input: ProductInput) => Promise<boolean>;
  onLocation: (input: LocationInput) => Promise<boolean>;
  onSeaportCountry: (countryCode: string) => Promise<void>;
};

type EntryMode = "catalog" | "manual";

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

export function ReferenceSetupPanel({
  busy,
  locations,
  seaportCatalogBusy,
  seaportCatalogError,
  seaportCatalogVersion,
  seaportCountries,
  seaports,
  onProduct,
  onLocation,
  onSeaportCountry,
}: Props) {
  const [product, setProduct] = useState(emptyProduct);
  const [location, setLocation] = useState(emptyLocation);
  const [entryMode, setEntryMode] = useState<EntryMode>("catalog");
  const [selectedCountry, setSelectedCountry] = useState("");
  const [selectedPort, setSelectedPort] = useState("");
  const [createdLocation, setCreatedLocation] = useState<LocationInput>();

  const normalizedLocation = useMemo(() => normalizeLocation(location), [location]);
  const duplicateLocation = locations.find(
    (candidate) =>
      candidate.stable_identifier.toUpperCase() ===
      normalizedLocation.stable_identifier.toUpperCase(),
  );
  const selectedCountryRecord = seaportCountries.find(
    (country) => country.country_code === selectedCountry,
  );
  const catalogSelectionReady = entryMode === "manual" || selectedPort !== "";
  const locationReady =
    catalogSelectionReady && validLocation(normalizedLocation) && duplicateLocation === undefined;

  async function submitProduct(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (await onProduct(product)) setProduct(emptyProduct);
  }

  async function submitLocation(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!locationReady) return;
    if (await onLocation(normalizedLocation)) {
      setCreatedLocation(normalizedLocation);
      setSelectedPort("");
      setLocation(
        entryMode === "catalog"
          ? { ...emptyLocation, country_code: selectedCountry }
          : emptyLocation,
      );
    }
  }

  function updateLocation(change: Partial<LocationInput>) {
    setCreatedLocation(undefined);
    setLocation((current) => ({ ...current, ...change }));
  }

  function changeMode(mode: EntryMode) {
    setEntryMode(mode);
    setSelectedCountry("");
    setSelectedPort("");
    setCreatedLocation(undefined);
    setLocation(emptyLocation);
    void onSeaportCountry("");
  }

  function chooseCountry(countryCode: string) {
    setSelectedCountry(countryCode);
    setSelectedPort("");
    updateLocation({
      ...emptyLocation,
      country_code: countryCode,
    });
    void onSeaportCountry(countryCode);
  }

  function choosePort(referenceCode: string) {
    setSelectedPort(referenceCode);
    const port = seaports.find((candidate) => candidate.reference_code === referenceCode);
    if (port === undefined) {
      updateLocation({ stable_identifier: "", name: "" });
      return;
    }

    updateLocation({
      stable_identifier: port.reference_code,
      name: port.name,
      country_code: port.country_code,
      location_kind: "port",
      reason: "Create a governed route location from the standard seaport directory",
    });
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

      <form
        className="command-form compact-form location-form"
        onSubmit={(event) => void submitLocation(event)}
      >
        <div className="reference-form-heading">
          <div>
            <span className="eyebrow">Location authority</span>
            <h2>Create route location</h2>
          </div>
          <span className="authority-count">{locations.length} active</span>
        </div>
        <p className="reference-intro">
          Choose an origin or destination country, then promote a standard seaport into this
          tenant&apos;s route authority.
        </p>

        <div className="reference-mode" role="group" aria-label="Location entry method">
          <button
            className={entryMode === "catalog" ? "reference-mode--active" : ""}
            type="button"
            aria-pressed={entryMode === "catalog"}
            onClick={() => changeMode("catalog")}
          >
            Standard seaport
          </button>
          <button
            className={entryMode === "manual" ? "reference-mode--active" : ""}
            type="button"
            aria-pressed={entryMode === "manual"}
            onClick={() => changeMode("manual")}
          >
            Manual exception
          </button>
        </div>

        {entryMode === "catalog" ? (
          <SeaportFields
            busy={seaportCatalogBusy}
            catalogError={seaportCatalogError}
            catalogVersion={seaportCatalogVersion}
            countries={seaportCountries}
            country={selectedCountry}
            countryRecord={selectedCountryRecord}
            port={selectedPort}
            ports={seaports}
            onCountry={chooseCountry}
            onPort={choosePort}
          />
        ) : (
          <ManualLocationFields
            location={location}
            normalized={normalizedLocation}
            onChange={updateLocation}
          />
        )}

        {duplicateLocation === undefined ? null : (
          <p className="field-message field-message--notice" role="status">
            {duplicateLocation.name} ({duplicateLocation.stable_identifier}) is already active. It
            can be selected directly in a sourcing lane.
          </p>
        )}

        <LocationPreview location={normalizedLocation} />

        {createdLocation === undefined ? null : (
          <p className="reference-success" role="status">
            {title(createdLocation.location_kind)} {createdLocation.name} is active and ready for a
            sourcing lane.
          </p>
        )}

        <button disabled={busy || seaportCatalogBusy || !locationReady}>
          {duplicateLocation === undefined
            ? `Create active ${entryMode === "catalog" ? "seaport" : "location"}`
            : "Location already active"}
        </button>
      </form>
    </div>
  );
}

function normalizeLocation(location: LocationInput): LocationInput {
  return {
    ...location,
    stable_identifier: location.stable_identifier.trim(),
    name: location.name.trim(),
    country_code: location.country_code.trim().toUpperCase(),
  };
}

function validLocation(location: LocationInput) {
  return (
    /^[A-Za-z0-9][A-Za-z0-9._:/-]{2,99}$/.test(location.stable_identifier) &&
    location.name.length >= 2 &&
    location.name.length <= 200 &&
    /^[A-Z]{2}$/.test(location.country_code)
  );
}

function title(value: string) {
  return `${value.charAt(0).toUpperCase()}${value.slice(1)}`;
}
