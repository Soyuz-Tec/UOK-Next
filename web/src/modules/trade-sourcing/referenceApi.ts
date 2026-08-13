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

export const listProducts = (token: string) =>
  authorizedRequest<Product[]>("/api/v1/products?limit=100", token);

export const listLocations = (token: string) =>
  authorizedRequest<Location[]>("/api/v1/locations?limit=100", token);

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
