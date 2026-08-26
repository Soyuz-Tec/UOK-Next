defmodule UokNext.OperationalReportingFixtures do
  @moduledoc false

  alias UokNext.Modules.Trade.Shipments.Public, as: Shipments
  alias UokNext.ProcurementFixtures

  def completed_readiness(context, decision \\ "go") when decision in ~w(go hold) do
    source = ProcurementFixtures.approved_proposal(context)

    {:ok, readiness, :executed} =
      Shipments.create_readiness_case(
        %{
          "stable_identifier" => unique("shipment-readiness"),
          "purchase_commitment_proposal_id" => source.proposal["id"],
          "expected_proposal_version" => source.proposal["lock_version"],
          "reason" => "Create a reportable shipment-readiness case"
        },
        source.proposal["lock_version"],
        context,
        Ecto.UUID.generate()
      )

    evidence_id =
      ProcurementFixtures.persisted_evidence(
        context,
        "shipment_readiness_case",
        readiness["id"],
        "operational report readiness evidence"
      )

    {:ok, submitted, :executed} =
      Shipments.submit_readiness_evidence(
        readiness["id"],
        %{"evidence_id" => evidence_id, "reason" => "Attach report-grade evidence"},
        readiness["lock_version"],
        context,
        Ecto.UUID.generate()
      )

    {:ok, completed, :executed} =
      Shipments.decide_readiness(
        submitted["id"],
        %{
          "decision" => decision,
          "reason" => "Record reportable #{String.upcase(decision)} decision",
          "task_id" => submitted["review_task"]["id"]
        },
        submitted["lock_version"],
        context,
        Ecto.UUID.generate()
      )

    Map.put(source, :readiness, completed)
  end

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
