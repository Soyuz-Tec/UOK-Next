defmodule UokNext.Modules.Trade.Sourcing.ProcurementPublicTest do
  use UokNext.DataCase, async: true

  import UokNext.PartyOnboardingFixtures

  alias UokNext.Kernel.TenantTransaction
  alias UokNext.Modules.Master.Locations.Public, as: Locations
  alias UokNext.Modules.Master.Parties.Public, as: Parties
  alias UokNext.Modules.Master.Products.Public, as: Products
  alias UokNext.Modules.Platform.Evidence.Infrastructure.EvidenceCandidateRecord

  alias UokNext.Modules.Trade.Sourcing.Infrastructure.{
    PurchaseRequisitionRecord,
    QuoteComparisonRecord,
    RfqRecord,
    SupplierQuoteRecord
  }

  alias UokNext.Modules.Trade.Sourcing.Public, as: Sourcing

  @permissions [
    "evidence:read",
    "evidence:upload",
    "locations:create",
    "locations:read",
    "parties:approve",
    "parties:create",
    "parties:evidence:submit",
    "parties:read",
    "products:create",
    "products:read",
    "sourcing:comparisons:approve",
    "sourcing:comparisons:create",
    "sourcing:comparisons:read",
    "sourcing:lanes:approve",
    "sourcing:lanes:create",
    "sourcing:lanes:evidence:submit",
    "sourcing:lanes:read",
    "sourcing:quotes:create",
    "sourcing:quotes:evidence:submit",
    "sourcing:quotes:read",
    "sourcing:requisitions:create",
    "sourcing:requisitions:read",
    "sourcing:rfqs:create",
    "sourcing:rfqs:read",
    "workflow:tasks:read"
  ]

  test "delivers an attributable and deterministic quote comparison with exact approval" do
    context = sourcing_context()
    round = open_round(context)
    first = submitted_quote(context, round, round.suppliers.first, "100.00", 14, "first")
    second = submitted_quote(context, round, round.suppliers.second, "90.00", 21, "second")

    third = submitted_quote(context, round, round.suppliers.third, "110.00", 10, "third")
    key = Ecto.UUID.generate()

    attrs = %{
      "stable_identifier" => unique("comparison"),
      "rfq_id" => round.rfq["id"],
      "reason" => "Compare attributable supplier offers"
    }

    assert {:ok, comparison, :executed} =
             Sourcing.create_quote_comparison(
               attrs,
               round.rfq["lock_version"],
               context,
               key
             )

    assert {:ok, ^comparison, :replayed} =
             Sourcing.create_quote_comparison(
               attrs,
               round.rfq["lock_version"],
               context,
               key
             )

    assert comparison["recommended_quote_id"] == second["id"]
    assert get_in(comparison, ["ranking_snapshot", "formula_version"]) == 1

    assert [best, other, last] = comparison["ranking_snapshot"]["ranking"]
    assert best["quote_id"] == second["id"]
    assert other["quote_id"] == first["id"]
    assert last["quote_id"] == third["id"]

    decision = %{
      "decision" => "approve",
      "reason" => "The deterministic comparison and evidence passed review",
      "task_id" => comparison["review_task"]["id"]
    }

    assert {:error, stale} =
             Sourcing.decide_quote_comparison(
               comparison["id"],
               decision,
               comparison["lock_version"] + 1,
               context,
               Ecto.UUID.generate()
             )

    assert stale.code == "stale_state"

    assert {:ok, approved, :executed} =
             Sourcing.decide_quote_comparison(
               comparison["id"],
               decision,
               comparison["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert approved["status"] == "approved"
    assert approved["review_task"]["resolution"] == "approve"
    assert count(PurchaseRequisitionRecord, context) == 1
    assert count(RfqRecord, context) == 1
    assert count(SupplierQuoteRecord, context) == 3
    assert count(QuoteComparisonRecord, context) == 1
  end

  test "keeps the RFQ open for every invited response until its deadline" do
    context = sourcing_context()
    round = open_round(context)

    _first = submitted_quote(context, round, round.suppliers.first, "100.00", 14, "first")
    _second = submitted_quote(context, round, round.suppliers.second, "90.00", 21, "second")

    assert {:error, conflict} =
             Sourcing.create_quote_comparison(
               %{
                 "stable_identifier" => unique("comparison-early-close"),
                 "rfq_id" => round.rfq["id"],
                 "reason" => "Attempt comparison before every invitee has submitted"
               },
               round.rfq["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert conflict.code == "state_conflict"
    assert conflict.message == "all invited suppliers must submit before an early comparison"
    assert count(QuoteComparisonRecord, context) == 0
  end

  test "fails closed for permissions, tenant substitution, invitations, and incomplete evidence" do
    owner = sourcing_context()
    round = open_round(owner)
    outsider = approved_party(owner, "outsider")

    assert {:error, not_invited} =
             Sourcing.create_supplier_quote(
               quote_attrs(round, outsider, "80.00", 10, "outsider"),
               owner,
               Ecto.UUID.generate()
             )

    assert not_invited.code == "not_found"

    foreign = sourcing_context()

    assert {:error, hidden} =
             Sourcing.create_supplier_quote(
               quote_attrs(round, round.suppliers.first, "80.00", 10, "foreign"),
               foreign,
               Ecto.UUID.generate()
             )

    assert hidden.code == "not_found"

    denied = sourcing_context(%{tenant_id: owner.tenant_id, permissions: []})

    assert {:error, forbidden} =
             Sourcing.create_supplier_quote(
               quote_attrs(round, round.suppliers.first, "80.00", 10, "denied"),
               denied,
               Ecto.UUID.generate()
             )

    assert forbidden.code == "forbidden"

    _one_quote =
      submitted_quote(owner, round, round.suppliers.first, "100.00", 14, "only")

    assert {:error, incomplete} =
             Sourcing.create_quote_comparison(
               %{
                 "stable_identifier" => unique("comparison"),
                 "rfq_id" => round.rfq["id"],
                 "reason" => "Attempt an incomplete comparison"
               },
               round.rfq["lock_version"],
               owner,
               Ecto.UUID.generate()
             )

    assert incomplete.code == "state_conflict"
    assert count(QuoteComparisonRecord, owner) == 0
  end

  defp open_round(context) do
    first = approved_party(context, "first")
    second = approved_party(context, "second")
    third = approved_party(context, "third")
    lane = approved_lane(context, first)

    requisition_attrs = %{
      "stable_identifier" => unique("requisition"),
      "sourcing_lane_id" => lane["id"],
      "quantity" => "25.000000",
      "unit_code" => "MT",
      "required_by" => Date.utc_today() |> Date.add(30) |> Date.to_iso8601(),
      "reason" => "Create a governed purchasing requirement"
    }

    {:ok, requisition, :executed} =
      Sourcing.create_requisition(requisition_attrs, context, Ecto.UUID.generate())

    rfq_attrs = %{
      "stable_identifier" => unique("rfq"),
      "requisition_id" => requisition["id"],
      "settlement_currency_code" => "USD",
      "response_deadline" =>
        DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601(),
      "supplier_party_ids" => [first["id"], second["id"], third["id"]],
      "reason" => "Invite approved suppliers to quote"
    }

    {:ok, rfq, :executed} =
      Sourcing.create_rfq(rfq_attrs, requisition["lock_version"], context, Ecto.UUID.generate())

    %{
      requisition: requisition,
      rfq: rfq,
      suppliers: %{first: first, second: second, third: third}
    }
  end

  defp submitted_quote(context, round, supplier, price, days, label) do
    {:ok, quote, :executed} =
      Sourcing.create_supplier_quote(
        quote_attrs(round, supplier, price, days, label),
        context,
        Ecto.UUID.generate()
      )

    evidence = persisted_evidence(context, "supplier_quote", quote["id"], label)

    {:ok, submitted, :executed} =
      Sourcing.submit_quote_evidence(
        quote["id"],
        %{"evidence_id" => evidence, "reason" => "Submit attributable quote evidence"},
        quote["lock_version"],
        context,
        Ecto.UUID.generate()
      )

    submitted
  end

  defp quote_attrs(round, supplier, price, days, label) do
    %{
      "stable_identifier" => unique("quote-#{label}"),
      "rfq_id" => round.rfq["id"],
      "supplier_party_id" => supplier["id"],
      "quoted_quantity" => "25",
      "unit_price" => price,
      "currency_code" => "USD",
      "delivery_days" => days,
      "reason" => "Record attributable supplier quote"
    }
  end

  defp approved_lane(context, supplier) do
    {:ok, product, :executed} =
      Products.create(
        %{
          "stable_identifier" => unique("product"),
          "name" => "Governed Product",
          "product_kind" => "commodity",
          "base_unit_code" => "MT",
          "reason" => "Create product authority"
        },
        context,
        Ecto.UUID.generate()
      )

    origin = location(context, "origin", "GH")
    destination = location(context, "destination", "GB")

    {:ok, lane, :executed} =
      Sourcing.create_lane(
        %{
          "stable_identifier" => unique("lane"),
          "name" => "Governed Sourcing Lane",
          "supplier_party_id" => supplier["id"],
          "product_id" => product["id"],
          "origin_location_id" => origin["id"],
          "destination_location_id" => destination["id"],
          "reason" => "Create governed sourcing lane"
        },
        context,
        Ecto.UUID.generate()
      )

    evidence = persisted_evidence(context, "sourcing_lane", lane["id"], "lane")

    {:ok, evidenced, :executed} =
      Sourcing.submit_evidence(
        lane["id"],
        %{
          "evidence_id" => evidence,
          "reason" => "Submit lane authority evidence"
        },
        lane["lock_version"],
        context,
        Ecto.UUID.generate()
      )

    {:ok, approved, :executed} =
      Sourcing.decide(
        lane["id"],
        %{
          "decision" => "approve",
          "reason" => "Lane evidence passed review",
          "task_id" => evidenced["review_task"]["id"]
        },
        evidenced["lock_version"],
        context,
        Ecto.UUID.generate()
      )

    approved
  end

  defp approved_party(context, label) do
    party = create_party(context, %{"stable_identifier" => unique("supplier-#{label}")})

    {:ok, evidenced, :executed} =
      Parties.submit_evidence(
        party["id"],
        persisted_evidence_attrs(context, party),
        party["lock_version"],
        context,
        Ecto.UUID.generate()
      )

    {:ok, approved, :executed} =
      Parties.decide(
        party["id"],
        %{
          "decision" => "approve",
          "reason" => "Supplier evidence passed review",
          "task_id" => evidenced["review_task"]["id"]
        },
        evidenced["lock_version"],
        context,
        Ecto.UUID.generate()
      )

    approved
  end

  defp location(context, label, country) do
    {:ok, location, :executed} =
      Locations.create(
        %{
          "stable_identifier" => unique(label),
          "name" => "#{String.capitalize(label)} Location",
          "country_code" => country,
          "location_kind" => "port",
          "reason" => "Create route location"
        },
        context,
        Ecto.UUID.generate()
      )

    location
  end

  defp persisted_evidence(context, subject_type, subject_id, label) do
    id = Ecto.UUID.generate()
    sha256 = :crypto.hash(:sha256, label) |> Base.encode16(case: :lower)
    now = DateTime.utc_now()

    attrs = %{
      id: id,
      tenant_id: context.tenant_id,
      subject_type: subject_type,
      subject_id: subject_id,
      content_type: "text/plain",
      byte_size: 128,
      sha256: sha256,
      object_key: "tenants/#{context.tenant_id}/evidence/#{id}/sha256/#{sha256}",
      classification: "confidential"
    }

    {:ok, _record} =
      TenantTransaction.run(context, fn ->
        %EvidenceCandidateRecord{}
        |> EvidenceCandidateRecord.create_changeset(attrs)
        |> Ecto.Changeset.change(%{
          state: "verified",
          storage_receipt: %{"receipt_sha256" => String.duplicate("e", 64)},
          verified_at: now
        })
        |> Repo.insert()
      end)

    id
  end

  defp sourcing_context(overrides \\ %{}),
    do: context(Map.merge(%{permissions: @permissions}, overrides))

  defp count(schema, context) do
    TenantTransaction.run(context, fn ->
      Repo.aggregate(
        from(record in schema, where: record.tenant_id == ^context.tenant_id),
        :count
      )
    end)
  end

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
