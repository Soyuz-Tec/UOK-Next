export const emptyPartyForm = {
  stable_identifier: "",
  legal_name: "",
  country_code: "",
  party_kind: "organization" as const,
  reason: "Begin governed party onboarding",
};

export type PartyForm = typeof emptyPartyForm;
