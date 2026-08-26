defmodule UokNext.Modules.Intelligence.Bi.OperationalReportTest do
  use UokNext.DataCase, async: true

  import Ecto.Query

  alias UokNext.Kernel.{AuditEvent, TenantTransaction}
  alias UokNext.Modules.Intelligence.Bi.Public, as: BusinessIntelligence
  alias UokNext.Modules.Trade.Contracts.Infrastructure.PurchaseCommitmentProposalRecord
  alias UokNext.OperationalReportingFixtures
  alias UokNext.ProcurementFixtures
  alias UokNext.Repo

  @source_read_permissions [
    "reports:operational:read",
    "shipments:readiness:read",
    "contracts:commitment-proposals:read",
    "sourcing:comparisons:read",
    "sourcing:lanes:read",
    "parties:read",
    "products:read",
    "locations:read",
    "evidence:read"
  ]

  test "projects one deterministic, reconciled, no-authority operational report" do
    context = ProcurementFixtures.context()
    source = OperationalReportingFixtures.completed_readiness(context)

    assert {:ok, first} = report(source.readiness, context)
    assert {:ok, second} = report(source.readiness, context)

    assert first["projection_id"] == second["projection_id"]
    assert first["reconciliation"]["projection_sha256"] == first["projection_id"]
    assert first["reconciliation"]["status"] == "reconciled"
    assert first["freshness"]["mode"] == "live_repeatable_read"
    assert first["freshness"]["maximum_staleness_seconds"] == 0

    assert first["grain"] == %{
             "type" => "shipment_readiness_case",
             "id" => source.readiness["id"],
             "version" => source.readiness["lock_version"]
           }

    assert first["outcome"] == "ready"

    assert Enum.map(first["stages"], & &1["code"]) ==
             ~w(party_onboarding sourcing_lane rfq quote_comparison commitment_proposal shipment_readiness)

    assert Decimal.equal?(
             Decimal.new(first["metrics"]["commercial"]["approved_total"]),
             Decimal.new("2250")
           )

    assert first["metrics"]["commercial"]["currency_conversion_applied"] == false
    assert length(first["evidence_lineage"]) == 5
    assert first["metrics"]["lineage"]["verified_evidence_count"] == 5
    assert first["audit_events"] != []
    assert first["delivery_events"] != []
    assert Enum.all?(first["audit_events"], &(not Map.has_key?(&1, "metadata")))
    assert Enum.all?(first["delivery_events"], &(not Map.has_key?(&1, "payload")))

    assert first["authority"] == %{
             "source_of_truth" => false,
             "business_mutation_authorized" => false,
             "external_effect_created" => false
           }
  end

  test "fails closed when the report or any source permission class is absent" do
    owner = ProcurementFixtures.context()
    source = OperationalReportingFixtures.completed_readiness(owner)

    Enum.each(@source_read_permissions, fn omitted ->
      permissions = ProcurementFixtures.permissions() -- [omitted]

      denied =
        ProcurementFixtures.context(%{tenant_id: owner.tenant_id, permissions: permissions})

      assert {:error, error} = report(source.readiness, denied)
      assert error.code == "forbidden", "expected #{omitted} to remain mandatory"
    end)
  end

  test "hides a foreign tenant and rejects stale or drifted source state" do
    context = ProcurementFixtures.context()
    source = OperationalReportingFixtures.completed_readiness(context)
    foreign = ProcurementFixtures.context()

    assert {:error, hidden} = report(source.readiness, foreign)
    assert hidden.code == "not_found"

    assert {:error, stale} =
             BusinessIntelligence.operational_report(
               source.readiness["id"],
               source.readiness["lock_version"] + 1,
               context
             )

    assert stale.code == "stale_state"

    TenantTransaction.run(context, fn ->
      Repo.update_all(
        from(proposal in PurchaseCommitmentProposalRecord,
          where:
            proposal.id == ^source.proposal["id"] and proposal.tenant_id == ^context.tenant_id
        ),
        inc: [lock_version: 1]
      )
    end)

    assert {:error, drifted} = report(source.readiness, context)
    assert drifted.code == "stale_state"
  end

  test "emits bounded success and rejection telemetry without subject labels" do
    context = ProcurementFixtures.context()
    source = OperationalReportingFixtures.completed_readiness(context)
    handler_id = "operational-report-test-#{Ecto.UUID.generate()}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:uok_next, :report, :stop],
        fn event, measurements, metadata, pid ->
          send(pid, {:report_telemetry, event, measurements, metadata})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:ok, _report} = report(source.readiness, context)

    assert_receive {:report_telemetry, [:uok_next, :report, :stop], %{duration: duration},
                    %{report: "gate3_operational_report_v1", outcome: "succeeded"}}

    assert is_integer(duration) and duration > 0

    denied = ProcurementFixtures.context(%{tenant_id: context.tenant_id, permissions: []})
    assert {:error, _error} = report(source.readiness, denied)

    assert_receive {:report_telemetry, [:uok_next, :report, :stop], _measurements,
                    %{report: "gate3_operational_report_v1", outcome: "rejected"}}
  end

  test "rejects a partial lineage instead of silently truncating report evidence" do
    context = ProcurementFixtures.context()
    source = OperationalReportingFixtures.completed_readiness(context)

    TenantTransaction.run(context, fn ->
      seed =
        Repo.one!(
          from(audit in AuditEvent,
            where:
              audit.tenant_id == ^context.tenant_id and
                audit.resource_type == "shipment_readiness_case" and
                audit.resource_id == ^source.readiness["id"],
            limit: 1
          )
        )

      now = DateTime.utc_now()

      rows =
        Enum.map(1..101, fn index ->
          %{
            id: Ecto.UUID.generate(),
            tenant_id: context.tenant_id,
            actor_id: context.actor_id,
            correlation_id: context.correlation_id,
            command_receipt_id: seed.command_receipt_id,
            action: "test.report_lineage_#{index}",
            resource_type: "shipment_readiness_case",
            resource_id: source.readiness["id"],
            outcome: "succeeded",
            reason: "Prove bounded operational-report lineage",
            classification: "internal",
            metadata: %{},
            occurred_at: now,
            inserted_at: now
          }
        end)

      Repo.insert_all(AuditEvent, rows)
    end)

    assert {:error, error} = report(source.readiness, context)
    assert error.code == "state_conflict"
  end

  defp report(readiness, context) do
    BusinessIntelligence.operational_report(
      readiness["id"],
      readiness["lock_version"],
      context
    )
  end
end
