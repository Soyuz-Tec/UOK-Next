import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, expect, test, vi } from "vitest";

import { ReferenceSetupPanel } from "./ReferenceSetupPanel";
import type { Location, LocationInput, MajorSeaport, MajorSeaportCountry } from "./referenceApi";

afterEach(cleanup);

const countries: MajorSeaportCountry[] = [
  { country_code: "GH", country_name: "Ghana", port_count: 2 },
];

const ports: MajorSeaport[] = [
  {
    reference_code: "GHTKD",
    country_code: "GH",
    country_name: "Ghana",
    name: "Takoradi",
    harbor_scale: "medium",
    catalog_number: "46040",
  },
  {
    reference_code: "GHTEM",
    country_code: "GH",
    country_name: "Ghana",
    name: "Tema",
    harbor_scale: "small",
    catalog_number: "46070",
  },
];

const existing: Location = {
  id: "33333333-3333-4333-8333-333333333333",
  stable_identifier: "GHTEM",
  name: "Tema",
  country_code: "GH",
  location_kind: "port",
  status: "active",
};

function renderPanel(
  options: {
    locations?: Location[];
    onLocation?: (input: LocationInput) => Promise<boolean>;
  } = {},
) {
  const onLocation = options.onLocation ?? vi.fn().mockResolvedValue(true);
  const onCountry = vi.fn().mockResolvedValue(undefined);

  render(
    <ReferenceSetupPanel
      busy={false}
      locations={options.locations ?? []}
      seaportCatalogBusy={false}
      seaportCatalogError={undefined}
      seaportCatalogVersion="2026-08-13-testcatalog"
      seaportCountries={countries}
      seaports={ports}
      onProduct={vi.fn().mockResolvedValue(true)}
      onLocation={onLocation}
      onSeaportCountry={onCountry}
    />,
  );

  return { onCountry, onLocation };
}

test("prefills a standardized seaport and blocks a duplicate tenant location", async () => {
  const user = userEvent.setup();
  const { onCountry, onLocation } = renderPanel({ locations: [existing] });

  await user.selectOptions(
    screen.getByRole("combobox", { name: /Origin or destination country/ }),
    "GH",
  );
  await user.selectOptions(screen.getByRole("combobox", { name: /Standard seaport/ }), "GHTEM");

  expect(onCountry).toHaveBeenCalledWith("GH");
  expect(screen.getByText(/Tema \(GHTEM\) is already active/)).toBeVisible();
  expect(screen.getByRole("button", { name: "Location already active" })).toBeDisabled();
  expect(onLocation).not.toHaveBeenCalled();
});

test("retains a manual exception after failure and clears it after success", async () => {
  const user = userEvent.setup();
  const onLocation = vi.fn().mockResolvedValueOnce(false).mockResolvedValueOnce(true);
  renderPanel({ onLocation });

  await user.click(screen.getByRole("button", { name: "Manual exception" }));
  await user.selectOptions(screen.getByRole("combobox", { name: "Location type" }), "facility");
  await user.type(screen.getByRole("textbox", { name: "Country code" }), "gh");
  await user.type(screen.getByRole("textbox", { name: "Location name" }), "Private terminal");
  await user.type(screen.getByRole("textbox", { name: /Permanent location code/ }), "GH-PRIVATE-1");

  await user.click(screen.getByRole("button", { name: "Create active location" }));
  expect(screen.getByRole("textbox", { name: "Location name" })).toHaveValue("Private terminal");

  await user.click(screen.getByRole("button", { name: "Create active location" }));
  expect(onLocation).toHaveBeenCalledTimes(2);
  expect(screen.getByText(/Facility Private terminal is active/)).toBeVisible();
  expect(screen.getByRole("textbox", { name: "Location name" })).toHaveValue("");
});
