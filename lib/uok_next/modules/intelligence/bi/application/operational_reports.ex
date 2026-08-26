defmodule UokNext.Modules.Intelligence.Bi.Application.OperationalReports do
  @moduledoc false

  alias UokNext.Kernel.{CommandError, TenantTransaction}
  alias UokNext.Modules.Intelligence.Bi.Domain.OperationalReport
  alias UokNext.Modules.Intelligence.Bi.Policies.Authorization
  alias UokNext.Modules.Master.{Locations, Parties, Products}
  alias UokNext.Modules.Platform.Evidence.Public, as: Evidence
  alias UokNext.Modules.Trade.{Shipments, Sourcing}

  @permission "reports:operational:read"
  @report_name "gate3_operational_report_v1"

  @spec get(String.t(), integer(), term()) :: {:ok, map()} | {:error, CommandError.t()}
  def get(readiness_id, expected_version, context) do
    started_at = System.monotonic_time()

    result =
      with :ok <- Authorization.require_permission(context, @permission),
           {:ok, id} <- cast_uuid(readiness_id),
           {:ok, version} <- cast_version(expected_version) do
        TenantTransaction.run_snapshot(context, fn -> project(id, version, context) end)
      end

    emit_telemetry(result, started_at)
    result
  end

  defp project(id, version, context) do
    with {:ok, readiness} <- Shipments.Public.operational_reporting_source(id, version, context),
         commercial = readiness["source_snapshot"]["commercial_source"],
         {:ok, lane} <- Sourcing.Public.get(commercial["sourcing_lane_id"], context),
         {:ok, party} <- Parties.Public.get(commercial["supplier_party_id"], context),
         {:ok, product} <- Products.Public.get(lane["product_id"], context),
         {:ok, origin} <- Locations.Public.get(lane["origin_location_id"], context),
         {:ok, destination} <- Locations.Public.get(lane["destination_location_id"], context),
         {:ok, lineage} <-
           Evidence.operational_lineage(refs(readiness, commercial, lane), context) do
      OperationalReport.build(%{
        readiness: readiness,
        lane: lane,
        party: party,
        product: product,
        origin: origin,
        destination: destination,
        lineage: lineage,
        observed_at: DateTime.utc_now()
      })
    end
  end

  defp refs(readiness, commercial, lane) do
    [
      ref("party", commercial["supplier_party_id"]),
      ref("product", lane["product_id"]),
      ref("location", lane["origin_location_id"]),
      ref("location", lane["destination_location_id"]),
      ref("sourcing_lane", commercial["sourcing_lane_id"]),
      ref("purchase_requisition", commercial["requisition_id"]),
      ref("rfq", commercial["rfq_id"]),
      ref("supplier_quote", commercial["selected_quote_id"]),
      ref("quote_comparison", commercial["quote_comparison_id"]),
      ref("purchase_commitment_proposal", readiness["purchase_commitment_proposal_id"]),
      ref("shipment_readiness_case", readiness["id"])
    ]
  end

  defp ref(type, id), do: %{type: type, id: id}

  defp cast_uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> validation(%{readiness_case_id: ["must be a UUID"]})
    end
  end

  defp cast_version(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp cast_version(_value), do: validation(%{expected_version: ["must be positive"]})

  defp validation(details) do
    {:error,
     CommandError.new("validation_failed", "operational report validation failed", 422, details)}
  end

  defp emit_telemetry(result, started_at) do
    :telemetry.execute(
      [:uok_next, :report, :stop],
      %{duration: System.monotonic_time() - started_at},
      %{report: @report_name, outcome: outcome(result)}
    )
  end

  defp outcome({:ok, _report}), do: "succeeded"
  defp outcome({:error, _error}), do: "rejected"
end
