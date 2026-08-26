defmodule UokNext.ProcurementFixtures do
  @moduledoc false

  alias UokNext.Kernel.TenantTransaction
  alias UokNext.Modules.Master.Locations.Public, as: Locations
  alias UokNext.Modules.Master.Parties.Public, as: Parties
  alias UokNext.Modules.Master.Products.Public, as: Products
  alias UokNext.Modules.Platform.Evidence.Infrastructure.EvidenceCandidateRecord
  alias UokNext.Modules.Trade.Contracts.Public, as: Contracts
  alias UokNext.Modules.Trade.Sourcing.Public, as: Sourcing
  alias UokNext.PartyOnboardingFixtures
  alias UokNext.Repo

  @permissions [
    "contracts:commitment-proposals:approve",
    "contracts:commitment-proposals:create",
    "contracts:commitment-proposals:evidence:submit",
    "contracts:commitment-proposals:read",
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
    "reports:operational:read",
    "shipments:readiness:create",
    "shipments:readiness:decide",
    "shipments:readiness:evidence:submit",
    "shipments:readiness:read",
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

  def permissions, do: @permissions

  def context(overrides \\ %{}) do
    PartyOnboardingFixtures.context(Map.merge(%{permissions: @permissions}, overrides))
  end

  def approved_comparison(context) do
    first = approved_party(context, "first")
    second = approved_party(context, "second")
    lane = approved_lane(context, first)

    {:ok, requisition, :executed} =
      Sourcing.create_requisition(
        %{
          "stable_identifier" => unique("requisition"),
          "sourcing_lane_id" => lane["id"],
          "quantity" => "25",
          "unit_code" => "MT",
          "required_by" => Date.utc_today() |> Date.add(30) |> Date.to_iso8601(),
          "reason" => "Create a governed purchasing requirement"
        },
        context,
        Ecto.UUID.generate()
      )

    {:ok, rfq, :executed} =
      Sourcing.create_rfq(
        %{
          "stable_identifier" => unique("rfq"),
          "requisition_id" => requisition["id"],
          "settlement_currency_code" => "USD",
          "response_deadline" =>
            DateTime.utc_now() |> DateTime.add(3_600, :second) |> DateTime.to_iso8601(),
          "supplier_party_ids" => [first["id"], second["id"]],
          "reason" => "Invite approved suppliers to quote"
        },
        requisition["lock_version"],
        context,
        Ecto.UUID.generate()
      )

    first_quote = submitted_quote(context, rfq, first, "100", 14, "first")
    selected_quote = submitted_quote(context, rfq, second, "90", 21, "second")

    {:ok, comparison, :executed} =
      Sourcing.create_quote_comparison(
        %{
          "stable_identifier" => unique("comparison"),
          "rfq_id" => rfq["id"],
          "reason" => "Compare attributable supplier offers"
        },
        rfq["lock_version"],
        context,
        Ecto.UUID.generate()
      )

    {:ok, approved, :executed} =
      Sourcing.decide_quote_comparison(
        comparison["id"],
        %{
          "decision" => "approve",
          "reason" => "Comparison evidence passed review",
          "task_id" => comparison["review_task"]["id"]
        },
        comparison["lock_version"],
        context,
        Ecto.UUID.generate()
      )

    %{
      comparison: approved,
      first_quote: first_quote,
      selected_quote: selected_quote,
      requisition: requisition,
      rfq: rfq
    }
  end

  def approved_proposal(context) do
    source = approved_comparison(context)

    {:ok, proposal, :executed} =
      Contracts.create_purchase_commitment_proposal(
        %{
          "stable_identifier" => unique("commitment-proposal"),
          "quote_comparison_id" => source.comparison["id"],
          "expected_comparison_version" => source.comparison["lock_version"],
          "reason" => "Create a source-derived proposal fixture"
        },
        source.comparison["lock_version"],
        context,
        Ecto.UUID.generate()
      )

    evidence_id =
      persisted_evidence(
        context,
        "purchase_commitment_proposal",
        proposal["id"],
        "commitment proposal"
      )

    {:ok, submitted, :executed} =
      Contracts.submit_purchase_commitment_evidence(
        proposal["id"],
        %{"evidence_id" => evidence_id, "reason" => "Submit proposal evidence fixture"},
        proposal["lock_version"],
        context,
        Ecto.UUID.generate()
      )

    {:ok, approved, :executed} =
      Contracts.decide_purchase_commitment_proposal(
        submitted["id"],
        %{
          "decision" => "approve",
          "reason" => "Approve proposal fixture",
          "task_id" => submitted["review_task"]["id"]
        },
        submitted["lock_version"],
        context,
        Ecto.UUID.generate()
      )

    Map.put(source, :proposal, approved)
  end

  def persisted_evidence(context, subject_type, subject_id, label) do
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

  defp approved_party(context, label) do
    party =
      PartyOnboardingFixtures.create_party(context, %{
        "stable_identifier" => unique("supplier-#{label}")
      })

    {:ok, evidenced, :executed} =
      Parties.submit_evidence(
        party["id"],
        PartyOnboardingFixtures.persisted_evidence_attrs(context, party),
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

    evidence_id = persisted_evidence(context, "sourcing_lane", lane["id"], "lane")

    {:ok, evidenced, :executed} =
      Sourcing.submit_evidence(
        lane["id"],
        %{"evidence_id" => evidence_id, "reason" => "Submit lane authority evidence"},
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

  defp submitted_quote(context, rfq, supplier, price, days, label) do
    {:ok, quote, :executed} =
      Sourcing.create_supplier_quote(
        %{
          "stable_identifier" => unique("quote-#{label}"),
          "rfq_id" => rfq["id"],
          "supplier_party_id" => supplier["id"],
          "quoted_quantity" => "25",
          "unit_price" => price,
          "currency_code" => "USD",
          "delivery_days" => days,
          "reason" => "Record attributable supplier quote"
        },
        context,
        Ecto.UUID.generate()
      )

    evidence_id = persisted_evidence(context, "supplier_quote", quote["id"], label)

    {:ok, submitted, :executed} =
      Sourcing.submit_quote_evidence(
        quote["id"],
        %{"evidence_id" => evidence_id, "reason" => "Submit attributable quote evidence"},
        quote["lock_version"],
        context,
        Ecto.UUID.generate()
      )

    submitted
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

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
