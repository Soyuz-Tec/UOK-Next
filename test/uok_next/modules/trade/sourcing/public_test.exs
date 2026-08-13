defmodule UokNext.Modules.Trade.Sourcing.PublicTest do
  use UokNext.DataCase, async: true

  import UokNext.PartyOnboardingFixtures

  alias UokNext.Kernel.{AuditEvent, CommandReceipt, OutboxEvent, TenantTransaction}
  alias UokNext.Modules.Master.Locations.Public, as: Locations
  alias UokNext.Modules.Master.Parties.Public, as: Parties
  alias UokNext.Modules.Master.Products.Public, as: Products
  alias UokNext.Modules.Platform.Evidence.Infrastructure.EvidenceCandidateRecord
  alias UokNext.Modules.Platform.Workflow.Infrastructure.HumanTaskRecord
  alias UokNext.Modules.Trade.Sourcing.Infrastructure.SourcingLaneRecord
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
    "sourcing:lanes:approve",
    "sourcing:lanes:create",
    "sourcing:lanes:evidence:submit",
    "sourcing:lanes:read",
    "workflow:tasks:read"
  ]

  test "creates and replays one lane with tenant-scoped references and command evidence" do
    context = sourcing_context()
    references = references(context)
    attrs = lane_attrs(references)
    key = Ecto.UUID.generate()
    before = counts(context)

    assert {:ok, lane, :executed} = Sourcing.create_lane(attrs, context, key)
    assert {:ok, ^lane, :replayed} = Sourcing.create_lane(attrs, context, key)
    assert lane["status"] == "draft"
    assert lane["tenant_id"] == context.tenant_id
    assert count(SourcingLaneRecord, context) == 1
    assert deltas(before, counts(context)) == %{audits: 1, events: 1, receipts: 1, tasks: 0}
  end

  test "hides cross-tenant references and denies missing named permissions" do
    owner_context = sourcing_context()
    references = references(owner_context)
    foreign_context = sourcing_context()

    assert {:error, hidden} =
             Sourcing.create_lane(lane_attrs(references), foreign_context, Ecto.UUID.generate())

    assert hidden.code == "not_found"
    assert count(CommandReceipt, foreign_context) == 0

    denied_context =
      sourcing_context(%{
        tenant_id: owner_context.tenant_id,
        permissions: ["parties:read", "products:read", "locations:read"]
      })

    assert {:error, denied} =
             Sourcing.create_lane(lane_attrs(references), denied_context, Ecto.UUID.generate())

    assert denied.code == "forbidden"
  end

  test "binds verified evidence and exact task to a versioned human decision" do
    context = sourcing_context()
    lane = create_lane(context)
    evidence = persisted_lane_evidence(context, lane)
    evidence_key = Ecto.UUID.generate()

    assert {:ok, evidenced, :executed} =
             Sourcing.submit_evidence(
               lane["id"],
               evidence,
               lane["lock_version"],
               context,
               evidence_key
             )

    assert {:ok, ^evidenced, :replayed} =
             Sourcing.submit_evidence(
               lane["id"],
               evidence,
               lane["lock_version"],
               context,
               evidence_key
             )

    assert evidenced["status"] == "evidence_submitted"
    assert evidenced["lock_version"] == 2
    assert count(HumanTaskRecord, context) == 2

    assert {:error, stale} =
             Sourcing.decide(
               lane["id"],
               decision(evidenced["review_task"]["id"]),
               lane["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert stale.code == "stale_state"

    assert {:error, wrong_task} =
             Sourcing.decide(
               lane["id"],
               decision(Ecto.UUID.generate()),
               evidenced["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert wrong_task.code == "not_found"

    decision_key = Ecto.UUID.generate()
    command = decision(evidenced["review_task"]["id"])

    assert {:ok, approved, :executed} =
             Sourcing.decide(
               lane["id"],
               command,
               evidenced["lock_version"],
               context,
               decision_key
             )

    assert {:ok, ^approved, :replayed} =
             Sourcing.decide(
               lane["id"],
               command,
               evidenced["lock_version"],
               context,
               decision_key
             )

    assert approved["status"] == "approved"
    assert approved["review_task"]["resolution"] == "approve"
  end

  test "reopens a held lane with clean decision state and a new exact review task" do
    context = sourcing_context()
    lane = create_lane(context)

    assert {:ok, first_submission, :executed} =
             Sourcing.submit_evidence(
               lane["id"],
               persisted_lane_evidence(context, lane),
               lane["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    first_task_id = first_submission["review_task"]["id"]

    assert {:ok, held, :executed} =
             Sourcing.decide(
               lane["id"],
               decision(first_task_id, "hold"),
               first_submission["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert held["status"] == "hold"

    assert {:ok, resubmitted, :executed} =
             Sourcing.submit_evidence(
               lane["id"],
               persisted_lane_evidence(context, lane),
               held["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert resubmitted["status"] == "evidence_submitted"
    assert resubmitted["lock_version"] == held["lock_version"] + 1
    refute resubmitted["review_task"]["id"] == first_task_id

    record =
      TenantTransaction.run(context, fn ->
        Repo.get!(SourcingLaneRecord, lane["id"])
      end)

    assert is_nil(record.decision_reason)
    assert is_nil(record.decision_actor_id)
    assert is_nil(record.decided_at)

    assert {:error, old_task} =
             Sourcing.decide(
               lane["id"],
               decision(first_task_id),
               resubmitted["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert old_task.code == "validation_failed"

    assert {:ok, approved, :executed} =
             Sourcing.decide(
               lane["id"],
               decision(resubmitted["review_task"]["id"]),
               resubmitted["lock_version"],
               context,
               Ecto.UUID.generate()
             )

    assert approved["status"] == "approved"
    assert approved["review_task"]["resolution"] == "approve"
  end

  test "reference commands fail closed without create permissions" do
    context = sourcing_context(%{permissions: []})

    assert {:error, product_denied} =
             Products.create(product_attrs(), context, Ecto.UUID.generate())

    assert product_denied.code == "forbidden"

    assert {:error, location_denied} =
             Locations.create(location_attrs("origin"), context, Ecto.UUID.generate())

    assert location_denied.code == "forbidden"
  end

  defp sourcing_context(overrides \\ %{}) do
    context(Map.merge(%{permissions: @permissions}, overrides))
  end

  defp references(context) do
    %{
      supplier: approved_party(context),
      product: create_product(context),
      origin: create_location(context, "origin"),
      destination: create_location(context, "destination")
    }
  end

  defp approved_party(context) do
    party = create_party(context)

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
        decision(evidenced["review_task"]["id"]),
        evidenced["lock_version"],
        context,
        Ecto.UUID.generate()
      )

    approved
  end

  defp create_product(context) do
    {:ok, product, :executed} =
      Products.create(product_attrs(), context, Ecto.UUID.generate())

    product
  end

  defp create_location(context, label) do
    {:ok, location, :executed} =
      Locations.create(location_attrs(label), context, Ecto.UUID.generate())

    location
  end

  defp create_lane(context) do
    {:ok, lane, :executed} =
      Sourcing.create_lane(lane_attrs(references(context)), context, Ecto.UUID.generate())

    lane
  end

  defp product_attrs do
    %{
      "stable_identifier" => unique("product"),
      "name" => "Governed Product",
      "product_kind" => "commodity",
      "base_unit_code" => "MT",
      "reason" => "Create governed product authority"
    }
  end

  defp location_attrs(label) do
    %{
      "stable_identifier" => unique(label),
      "name" => "#{String.capitalize(label)} Location",
      "country_code" => "GH",
      "location_kind" => "port",
      "reason" => "Create governed route location"
    }
  end

  defp lane_attrs(references) do
    %{
      "stable_identifier" => unique("lane"),
      "name" => "Governed Sourcing Lane",
      "supplier_party_id" => references.supplier["id"],
      "product_id" => references.product["id"],
      "origin_location_id" => references.origin["id"],
      "destination_location_id" => references.destination["id"],
      "reason" => "Create governed sourcing authority"
    }
  end

  defp persisted_lane_evidence(context, lane) do
    evidence_id = Ecto.UUID.generate()
    sha256 = String.duplicate("c", 64)
    now = DateTime.utc_now()

    attrs = %{
      id: evidence_id,
      tenant_id: context.tenant_id,
      subject_type: "sourcing_lane",
      subject_id: lane["id"],
      content_type: "text/plain",
      byte_size: 128,
      sha256: sha256,
      object_key: "tenants/#{context.tenant_id}/evidence/#{evidence_id}/sha256/#{sha256}",
      classification: "confidential"
    }

    {:ok, _record} =
      TenantTransaction.run(context, fn ->
        %EvidenceCandidateRecord{}
        |> EvidenceCandidateRecord.create_changeset(attrs)
        |> Ecto.Changeset.change(%{
          state: "verified",
          storage_receipt: %{"receipt_sha256" => String.duplicate("d", 64)},
          verified_at: now
        })
        |> Repo.insert()
      end)

    %{
      "evidence_id" => evidence_id,
      "sha256" => sha256,
      "classification" => "confidential",
      "reason" => "Attach verified sourcing authority evidence"
    }
  end

  defp decision(task_id, outcome \\ "approve") do
    %{
      "decision" => outcome,
      "reason" => "Evidence received governed #{outcome} review",
      "task_id" => task_id
    }
  end

  defp count(schema, context) do
    TenantTransaction.run(context, fn ->
      Repo.aggregate(
        from(record in schema, where: record.tenant_id == ^context.tenant_id),
        :count
      )
    end)
  end

  defp counts(context) do
    %{
      receipts: count(CommandReceipt, context),
      audits: count(AuditEvent, context),
      events: count(OutboxEvent, context),
      tasks: count(HumanTaskRecord, context)
    }
  end

  defp deltas(before, after_counts) do
    Map.new(after_counts, fn {key, value} -> {key, value - Map.fetch!(before, key)} end)
  end

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
