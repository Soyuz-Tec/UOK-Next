import { authorizedRequest } from "../../shared/authorizedApi";

export type Product = {
  id: string;
  stable_identifier: string;
  name: string;
  product_kind: "commodity" | "packaging" | "service";
  base_unit_code: string;
  status: "active";
};

export type Location = {
  id: string;
  stable_identifier: string;
  name: string;
  country_code: string;
  location_kind: "country" | "region" | "locality" | "port" | "facility";
  status: "active";
};

export type ProductInput = Omit<Product, "id" | "status"> & { reason: string };
export type LocationInput = Omit<Location, "id" | "status"> & { reason: string };

export type MajorSeaportCountry = {
  country_code: string;
  country_name: string;
  port_count: number;
};

export type MajorSeaport = {
  reference_code: string;
  country_code: string;
  country_name: string;
  name: string;
  harbor_scale: "large" | "medium" | "small" | "very_small" | "unclassified";
  catalog_number: string;
};

export type MajorSeaportCatalog<T> = {
  catalog_version: string;
  items: T[];
};

export const listProducts = (token: string) =>
  authorizedRequest<Product[]>("/api/v1/products?limit=100", token);

export const listLocations = (token: string) =>
  authorizedRequest<Location[]>("/api/v1/locations?limit=100", token);

export const listMajorSeaportCountries = (token: string) =>
  authorizedRequest<MajorSeaportCatalog<MajorSeaportCountry>>(
    "/api/v1/location-references/major-seaports/countries",
    token,
  );

export const listMajorSeaports = (token: string, countryCode: string, signal?: AbortSignal) =>
  authorizedRequest<MajorSeaportCatalog<MajorSeaport>>(
    `/api/v1/location-references/major-seaports?country_code=${encodeURIComponent(countryCode)}`,
    token,
    signal === undefined ? {} : { signal },
  );

export const createProduct = (token: string, input: ProductInput) =>
  authorizedRequest<Product>("/api/v1/products", token, {
    method: "POST",
    headers: { "content-type": "application/json", "idempotency-key": crypto.randomUUID() },
    body: JSON.stringify(input),
  });

export const createLocation = (token: string, input: LocationInput) =>
  authorizedRequest<Location>("/api/v1/locations", token, {
    method: "POST",
    headers: { "content-type": "application/json", "idempotency-key": crypto.randomUUID() },
    body: JSON.stringify(input),
  });
