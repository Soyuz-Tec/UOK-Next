defmodule UokNext.Modules.Intelligence.Bi.Domain.OperationalReport do
  @moduledoc "Pure version-one operational-report projection."

  alias UokNext.Kernel.CommandError

  @definition_version 1
  @authority_flags %{
    "source_of_truth" => false,
    "business_mutation_authorized" => false,
    "external_effect_created" => false
  }

  @spec build(map()) :: {:ok, map()} | {:error, CommandError.t()}
  def build(input) do
    with {:ok, commercial} <- commercial_source(input.readiness),
         :ok <- validate_current_dimensions(input, commercial),
         {:ok, evidence} <- evidence_lineage(input, commercial) do
      projection = projection(input, commercial, evidence)
      digest = digest(projection)

      {:ok,
       projection
       |> Map.put("projection_id", digest)
       |> Map.put("reconciliation", %{
         "status" => "reconciled",
         "definition_version" => @definition_version,
         "projection_sha256" => digest
       })
       |> Map.put("freshness", %{
         "observed_at" => DateTime.to_iso8601(input.observed_at),
         "mode" => "live_repeatable_read",
         "maximum_staleness_seconds" => 0
       })}
    end
  end

  defp validate_current_dimensions(input, commercial) do
    conditions = [
      input.party["status"] == "approved",
      input.party["id"] == commercial["supplier_party_id"],
      input.lane["status"] == "approved",
      input.lane["id"] == commercial["sourcing_lane_id"],
      input.lane["lock_version"] == commercial["sourcing_lane_version"],
      input.product["status"] == "active",
      input.product["id"] == input.lane["product_id"],
      input.origin["status"] == "active",
      input.origin["id"] == input.lane["origin_location_id"],
      input.destination["status"] == "active",
      input.destination["id"] == input.lane["destination_location_id"],
      input.origin["id"] != input.destination["id"]
    ]

    if Enum.all?(conditions), do: :ok, else: conflict()
  end

  defp commercial_source(readiness) do
    case get_in(readiness, ["source_snapshot", "commercial_source"]) do
      %{
        "quote_comparison_id" => _comparison_id,
        "rfq_id" => _rfq_id,
        "requisition_id" => _requisition_id,
        "selected_quote_id" => _quote_id,
        "total_price" => _total
      } = source ->
        {:ok, source}

      _invalid ->
        conflict()
    end
  end

  defp evidence_lineage(input, commercial) do
    candidates = [
      evidence("party_onboarding", input.party["evidence_metadata"]),
      evidence("sourcing_lane", input.lane["evidence_metadata"]),
      evidence("supplier_quote", commercial["quote_evidence"]),
      evidence("commitment_proposal", input.readiness["source_snapshot"]["proposal_evidence"]),
      evidence("shipment_readiness", input.readiness["evidence_metadata"])
    ]

    complete? =
      Enum.all?(candidates, &is_map/1) and
        input.lineage["audit_events_truncated"] == false and
        input.lineage["delivery_events_truncated"] == false

    if complete?, do: {:ok, candidates}, else: conflict()
  end

  defp evidence(stage, %{
         "evidence_id" => id,
         "sha256" => sha256,
         "classification" => classification
       })
       when is_binary(id) and is_binary(sha256) and is_binary(classification) do
    %{
      "stage" => stage,
      "evidence_id" => id,
      "sha256" => sha256,
      "classification" => classification,
      "state" => "verified"
    }
  end

  defp evidence(_stage, _metadata), do: nil

  defp projection(input, commercial, evidence) do
    %{
      "definition_version" => @definition_version,
      "grain" => %{
        "type" => "shipment_readiness_case",
        "id" => input.readiness["id"],
        "version" => input.readiness["lock_version"]
      },
      "outcome" => outcome(input.readiness["status"]),
      "stages" => stages(input, commercial),
      "dimensions" => dimensions(input),
      "metrics" => metrics(commercial, input.lineage, evidence),
      "evidence_lineage" => evidence,
      "audit_events" => input.lineage["audit_events"],
      "delivery_events" => input.lineage["delivery_events"],
      "delivery_status_counts" => input.lineage["delivery_status_counts"],
      "authority" => @authority_flags
    }
  end

  defp stages(input, commercial) do
    [
      stage(
        "party_onboarding",
        "party",
        input.party["id"],
        input.party["lock_version"],
        "approved"
      ),
      stage(
        "sourcing_lane",
        "sourcing_lane",
        input.lane["id"],
        input.lane["lock_version"],
        "approved"
      ),
      stage("rfq", "rfq", commercial["rfq_id"], commercial["rfq_version"], "compared"),
      stage(
        "quote_comparison",
        "quote_comparison",
        commercial["quote_comparison_id"],
        commercial["quote_comparison_version"],
        "approved"
      ),
      stage(
        "commitment_proposal",
        "purchase_commitment_proposal",
        input.readiness["purchase_commitment_proposal_id"],
        input.readiness["purchase_commitment_proposal_version"],
        "approved"
      ),
      stage(
        "shipment_readiness",
        "shipment_readiness_case",
        input.readiness["id"],
        input.readiness["lock_version"],
        input.readiness["status"]
      )
    ]
  end

  defp stage(code, type, id, version, status),
    do: %{
      "code" => code,
      "source_type" => type,
      "source_id" => id,
      "source_version" => version,
      "status" => status
    }

  defp dimensions(input) do
    %{
      "supplier" => Map.take(input.party, ~w(id stable_identifier legal_name country_code)),
      "product" => Map.take(input.product, ~w(id stable_identifier name base_unit_code)),
      "origin" =>
        Map.take(input.origin, ~w(id stable_identifier name location_kind country_code)),
      "destination" =>
        Map.take(input.destination, ~w(id stable_identifier name location_kind country_code)),
      "sourcing_lane" => Map.take(input.lane, ~w(id stable_identifier name))
    }
  end

  defp metrics(commercial, lineage, evidence) do
    %{
      "commercial" => %{
        "grain" => "approved_selected_quote",
        "quantity" => commercial["quantity"],
        "unit_code" => commercial["unit_code"],
        "unit_price" => commercial["unit_price"],
        "approved_total" => commercial["total_price"],
        "currency_code" => commercial["currency_code"],
        "delivery_days" => commercial["delivery_days"],
        "required_by" => commercial["required_by"],
        "currency_conversion_applied" => false
      },
      "lineage" => %{
        "verified_evidence_count" => length(evidence),
        "audit_event_count" => length(lineage["audit_events"]),
        "delivery_event_count" => length(lineage["delivery_events"])
      }
    }
  end

  defp outcome("go"), do: "ready"
  defp outcome("hold"), do: "held"
  defp outcome(_status), do: "in_progress"

  defp digest(projection) do
    projection
    |> canonicalize()
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp canonicalize(value) when is_map(value) do
    value
    |> Enum.map(fn {key, item} -> {to_string(key), canonicalize(item)} end)
    |> Enum.sort()
  end

  defp canonicalize(value) when is_list(value), do: Enum.map(value, &canonicalize/1)
  defp canonicalize(value), do: value

  defp conflict do
    {:error,
     CommandError.new(
       "state_conflict",
       "operational report source failed reconciliation",
       409
     )}
  end
end
