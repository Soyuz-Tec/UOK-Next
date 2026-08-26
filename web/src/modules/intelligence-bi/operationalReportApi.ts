import { authorizedRequest } from "../../shared/authorizedApi";

export type ReportStage = {
  code: string;
  source_type: string;
  source_id: string;
  source_version: number;
  status: string;
};

export type ReportEvidence = {
  stage: string;
  evidence_id: string;
  sha256: string;
  classification: string;
  state: "verified";
};

export type ReportAuditEvent = {
  id: string;
  action: string;
  resource_type: string;
  resource_id: string;
  outcome: string;
  reason: string;
  classification: string;
  actor_id: string;
  correlation_id: string;
  occurred_at: string;
};

export type ReportDeliveryEvent = {
  id: string;
  event_name: string;
  aggregate_type: string;
  aggregate_id: string;
  aggregate_version: number;
  status: "pending" | "publishing" | "published" | "dead_letter";
  attempt_count: number;
  available_at: string;
  published_at: string | null;
};

type NamedDimension = {
  id: string;
  stable_identifier: string;
  name: string;
};

export type OperationalReport = {
  definition_version: number;
  projection_id: string;
  grain: { type: "shipment_readiness_case"; id: string; version: number };
  outcome: "ready" | "held" | "in_progress";
  stages: ReportStage[];
  dimensions: {
    supplier: {
      id: string;
      stable_identifier: string;
      legal_name: string;
      country_code: string;
    };
    product: NamedDimension & { base_unit_code: string };
    origin: NamedDimension & { location_kind: string; country_code: string };
    destination: NamedDimension & { location_kind: string; country_code: string };
    sourcing_lane: NamedDimension;
  };
  metrics: {
    commercial: {
      grain: "approved_selected_quote";
      quantity: string;
      unit_code: string;
      unit_price: string;
      approved_total: string;
      currency_code: string;
      delivery_days: number;
      required_by: string;
      currency_conversion_applied: false;
    };
    lineage: {
      verified_evidence_count: number;
      audit_event_count: number;
      delivery_event_count: number;
    };
  };
  evidence_lineage: ReportEvidence[];
  audit_events: ReportAuditEvent[];
  delivery_events: ReportDeliveryEvent[];
  delivery_status_counts: Record<ReportDeliveryEvent["status"], number>;
  authority: {
    source_of_truth: false;
    business_mutation_authorized: false;
    external_effect_created: false;
  };
  freshness: {
    observed_at: string;
    mode: "live_repeatable_read";
    maximum_staleness_seconds: 0;
  };
  reconciliation: {
    status: "reconciled";
    definition_version: number;
    projection_sha256: string;
  };
};

export function getOperationalReport(token: string, readinessId: string, expectedVersion: number) {
  const query = new URLSearchParams({ expected_version: String(expectedVersion) });
  return authorizedRequest<OperationalReport>(
    `/api/v1/operational-reports/${readinessId}?${query.toString()}`,
    token,
  );
}
