import type { LocationInput, MajorSeaport, MajorSeaportCountry } from "./referenceApi";

type SeaportFieldsProps = {
  busy: boolean;
  catalogError: string | undefined;
  catalogVersion: string | undefined;
  countries: MajorSeaportCountry[];
  country: string;
  countryRecord: MajorSeaportCountry | undefined;
  port: string;
  ports: MajorSeaport[];
  onCountry: (countryCode: string) => void;
  onPort: (referenceCode: string) => void;
};

export function SeaportFields({
  busy,
  catalogError,
  catalogVersion,
  countries,
  country,
  countryRecord,
  port,
  ports,
  onCountry,
  onPort,
}: SeaportFieldsProps) {
  return (
    <div className="seaport-selector">
      <label>
        Origin or destination country
        <select
          value={country}
          disabled={busy}
          onChange={(event) => onCountry(event.currentTarget.value)}
        >
          <option value="">Choose a country</option>
          {countries.map((candidate) => (
            <option key={candidate.country_code} value={candidate.country_code}>
              {candidate.country_name} · {candidate.country_code} ({candidate.port_count})
            </option>
          ))}
        </select>
        <small className="field-hint">
          {countries.length} countries with standardized maritime locations are preloaded.
        </small>
      </label>
      <label>
        Standard seaport
        <select
          value={port}
          disabled={busy || country === ""}
          onChange={(event) => onPort(event.currentTarget.value)}
        >
          <option value="">
            {busy
              ? "Loading ports…"
              : country === ""
                ? "Choose a country first"
                : "Choose a seaport"}
          </option>
          {ports.map((candidate) => (
            <option key={candidate.reference_code} value={candidate.reference_code}>
              {candidate.name} · {candidate.reference_code} · {harborScale(candidate.harbor_scale)}
            </option>
          ))}
        </select>
        <small className="field-hint">
          Larger harbors are listed first; every choice carries a permanent standard code.
        </small>
      </label>
      <div className="catalog-status" aria-live="polite">
        <span>{countryRecord?.port_count ?? 0} ports available</span>
        <span>Catalog {catalogVersion ?? "loading"}</span>
      </div>
      {catalogError === undefined ? null : (
        <p className="field-message field-message--error" role="alert">
          {catalogError}. Use Manual exception while the directory is unavailable.
        </p>
      )}
    </div>
  );
}

type ManualLocationFieldsProps = {
  location: LocationInput;
  normalized: LocationInput;
  onChange: (change: Partial<LocationInput>) => void;
};

export function ManualLocationFields({
  location,
  normalized,
  onChange,
}: ManualLocationFieldsProps) {
  return (
    <div className="manual-location-fields">
      <div className="form-row">
        <label>
          Location type
          <select
            value={location.location_kind}
            onChange={(event) =>
              onChange({
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
        <label>
          Country code
          <input
            required
            minLength={2}
            maxLength={2}
            pattern="[A-Za-z]{2}"
            placeholder="GH"
            autoCapitalize="characters"
            aria-invalid={
              location.country_code.length > 0 && !/^[A-Z]{2}$/.test(normalized.country_code)
            }
            value={location.country_code}
            onChange={(event) =>
              onChange({ country_code: event.currentTarget.value.toUpperCase() })
            }
          />
        </label>
      </div>
      <label>
        Location name
        <input
          required
          minLength={2}
          maxLength={200}
          placeholder="Operator-recognized name"
          value={location.name}
          onChange={(event) => onChange({ name: event.currentTarget.value })}
        />
      </label>
      <label>
        Permanent location code
        <input
          required
          minLength={3}
          maxLength={100}
          pattern="[A-Za-z0-9][A-Za-z0-9._:/-]{2,99}"
          placeholder="TENANT-LOCATION-CODE"
          value={location.stable_identifier}
          onChange={(event) => onChange({ stable_identifier: event.currentTarget.value })}
        />
        <small className="field-hint">
          Manual entries are for valid locations absent from the standard directory.
        </small>
      </label>
    </div>
  );
}

export function LocationPreview({ location }: { location: LocationInput }) {
  return (
    <div className="location-preview" aria-live="polite">
      <span className="eyebrow">Creation preview</span>
      <strong>{location.name || "Choose a route location"}</strong>
      <div className="location-preview-grid">
        <span>
          <small>Type</small>
          {title(location.location_kind)}
        </span>
        <span>
          <small>Country</small>
          {location.country_code || "—"}
        </span>
        <span>
          <small>Permanent code</small>
          {location.stable_identifier || "—"}
        </span>
      </div>
    </div>
  );
}

function harborScale(value: MajorSeaport["harbor_scale"]) {
  return value === "unclassified"
    ? "Scale not classified"
    : `${title(value.replace("_", " "))} harbor`;
}

function title(value: string) {
  return `${value.charAt(0).toUpperCase()}${value.slice(1)}`;
}
