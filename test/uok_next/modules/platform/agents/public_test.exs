defmodule UokNext.Modules.Platform.Agents.PublicTest do
  use UokNext.DataCase, async: true

  alias UokNext.Kernel.{
    AuditEvent,
    CommandContext,
    CommandReceipt,
    OutboxEvent,
    TenantTransaction
  }

  alias UokNext.Modules.Platform.Agents.Infrastructure.AgentPlanRecord
  alias UokNext.Modules.Platform.Agents.Public
  alias UokNext.Modules.Platform.Integrations.Infrastructure.ConnectorReceiptRecord
  alias UokNext.Modules.Platform.Workflow.Infrastructure.HumanTaskRecord

  describe "governed plan lifecycle" do
    test "atomically proposes an immutable plan and exact human task" do
      context = context()

      assert {:ok, plan, :executed} =
               Public.propose_plan(plan_attrs(), context, Ecto.UUID.generate())

      assert plan["status"] == "proposed"
      assert plan["execution_authorized"] == false
      assert plan["lock_version"] == 1
      assert byte_size(plan["plan_sha256"]) == 64
      assert Enum.map(plan["steps"], & &1["id"]) == ["inspect", "recommend"]
      assert plan["review_task"]["status"] == "open"
      assert plan["review_task"]["subject_id"] == plan["id"]
      assert plan["review_task_id"] == plan["review_task"]["id"]

      assert counts(context) == %{
               plans: 1,
               tasks: 1,
               commands: 1,
               audits: 2,
               events: 2,
               connector_receipts: 0
             }
    end

    test "approval records review but never authorizes execution" do
      context = context()
      plan = propose(plan_attrs(), context)

      assert {:ok, approved, :executed} =
               Public.decide_plan(
                 plan["id"],
                 plan["lock_version"],
                 decision_attrs(plan),
                 context,
                 Ecto.UUID.generate()
               )

      assert approved["status"] == "approved"
      assert approved["execution_authorized"] == false
      assert approved["lock_version"] == 2
      assert approved["review_task"]["status"] == "completed"
      assert approved["review_task"]["resolution"] == "approve"

      assert counts(context) == %{
               plans: 1,
               tasks: 1,
               commands: 2,
               audits: 4,
               events: 4,
               connector_receipts: 0
             }
    end

    test "replays proposals and rejects idempotency substitution" do
      context = context()
      attrs = plan_attrs()
      key = Ecto.UUID.generate()

      assert {:ok, first, :executed} = Public.propose_plan(attrs, context, key)
      assert {:ok, ^first, :replayed} = Public.propose_plan(attrs, context, key)

      changed = put_in(attrs, ["steps", Access.at(0), "title"], "Inspect altered evidence")
      assert {:error, conflict} = Public.propose_plan(changed, context, key)
      assert conflict.code == "idempotency_conflict"
      assert tenant_count(AgentPlanRecord, context) == 1
      assert tenant_count(HumanTaskRecord, context) == 1
    end

    test "rejects duplicate plan content and rolls back the generated task" do
      context = context()
      attrs = plan_attrs()
      _first = propose(attrs, context)
      counts_before = counts(context)

      assert {:error, duplicate} = Public.propose_plan(attrs, context, Ecto.UUID.generate())
      assert duplicate.code == "validation_failed"
      assert counts(context) == counts_before
    end

    test "rejects malformed, cyclic, and executable plan graphs" do
      context = context()

      invalid_steps = [
        [step("same", "read"), step("same", "recommend")],
        [step("one", "read", ["missing"])],
        [step("one", "read", ["two"]), step("two", "recommend", ["one"])],
        [step("one", "execute")],
        [Map.put(step("one", "read"), "tool", "unsafe")],
        Enum.map(1..33, &step("step_#{&1}", "read"))
      ]

      Enum.each(invalid_steps, fn steps ->
        assert {:error, error} =
                 Public.propose_plan(
                   plan_attrs(%{"steps" => steps}),
                   context,
                   Ecto.UUID.generate()
                 )

        assert error.code == "validation_failed"
      end)

      assert counts(context) == %{
               plans: 0,
               tasks: 0,
               commands: 0,
               audits: 0,
               events: 0,
               connector_receipts: 0
             }
    end

    test "rejects stale state and task substitution atomically" do
      context = context()
      first = propose(plan_attrs(), context)
      second = propose(plan_attrs(%{"subject_id" => Ecto.UUID.generate()}), context)
      counts_before = counts(context)

      assert {:error, stale} =
               Public.decide_plan(
                 second["id"],
                 second["lock_version"] + 1,
                 decision_attrs(second),
                 context,
                 Ecto.UUID.generate()
               )

      assert stale.code == "stale_state"

      substituted = decision_attrs(second, %{"task_id" => first["review_task_id"]})

      assert {:error, mismatch} =
               Public.decide_plan(
                 second["id"],
                 second["lock_version"],
                 substituted,
                 context,
                 Ecto.UUID.generate()
               )

      assert mismatch.code == "validation_failed"
      assert counts(context) == counts_before
      assert Enum.all?(tenant_all(HumanTaskRecord, context), &(&1.status == "open"))
    end

    test "replays a decision but rejects consumed-task reuse" do
      context = context()
      plan = propose(plan_attrs(), context)
      decision = decision_attrs(plan)
      key = Ecto.UUID.generate()

      assert {:ok, approved, :executed} =
               Public.decide_plan(plan["id"], plan["lock_version"], decision, context, key)

      counts_after = counts(context)

      assert {:ok, ^approved, :replayed} =
               Public.decide_plan(plan["id"], plan["lock_version"], decision, context, key)

      assert {:error, consumed} =
               Public.decide_plan(
                 plan["id"],
                 approved["lock_version"],
                 decision,
                 context,
                 Ecto.UUID.generate()
               )

      assert consumed.code == "validation_failed"
      assert counts(context) == counts_after
    end
  end

  describe "authorization and tenant isolation" do
    test "denies proposal, decision, and read without their named permissions" do
      denied = context(%{permissions: []})

      assert {:error, proposal_denied} =
               Public.propose_plan(plan_attrs(), denied, Ecto.UUID.generate())

      assert proposal_denied.code == "forbidden"

      owner = context()
      plan = propose(plan_attrs(), owner)
      reader = context(%{tenant_id: owner.tenant_id, permissions: ["agents:plan:read"]})

      assert {:error, decision_denied} =
               Public.decide_plan(
                 plan["id"],
                 plan["lock_version"],
                 decision_attrs(plan),
                 reader,
                 Ecto.UUID.generate()
               )

      assert decision_denied.code == "forbidden"
      proposer = context(%{tenant_id: owner.tenant_id, permissions: ["agents:plan:propose"]})
      assert {:error, read_denied} = Public.get_plan(plan["id"], proposer)
      assert read_denied.code == "forbidden"
    end

    test "hides foreign tenant plans and review tasks" do
      owner = context()
      other = context()
      plan = propose(plan_attrs(), owner)

      assert {:error, hidden} = Public.get_plan(plan["id"], other)
      assert hidden.code == "not_found"

      assert {:error, hidden} =
               Public.decide_plan(
                 plan["id"],
                 plan["lock_version"],
                 decision_attrs(plan),
                 other,
                 Ecto.UUID.generate()
               )

      assert hidden.code == "not_found"
      assert tenant_count(AgentPlanRecord, owner) == 1
      assert tenant_count(HumanTaskRecord, owner) == 1
      assert tenant_count(AgentPlanRecord, other) == 0
      assert tenant_count(HumanTaskRecord, other) == 0
    end

    test "forced row-level security rejects unset and substituted tenant state" do
      owner = context()
      other = context()
      _plan = propose(plan_attrs(), owner)

      Repo.query!("SET LOCAL ROLE pg_read_all_data", [], log: false)
      Repo.query!("SELECT set_config('uok.tenant_id', '', true)", [], log: false)
      assert Repo.aggregate(AgentPlanRecord, :count) == 0
      assert tenant_count(AgentPlanRecord, other) == 0
      assert tenant_count(AgentPlanRecord, owner) == 1
    end
  end

  defp context(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          tenant_id: Ecto.UUID.generate(),
          actor_id: Ecto.UUID.generate(),
          correlation_id: Ecto.UUID.generate(),
          permissions: ["agents:plan:propose", "agents:plan:approve", "agents:plan:read"]
        },
        overrides
      )

    {:ok, context} = CommandContext.new(attrs)
    context
  end

  defp plan_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "runbook_key" => "party_onboarding_review",
        "runbook_version" => 1,
        "subject_type" => "party",
        "subject_id" => Ecto.UUID.generate(),
        "subject_version" => 1,
        "steps" => [
          step("inspect", "read"),
          step("recommend", "recommend", ["inspect"])
        ],
        "evidence_ids" => [Ecto.UUID.generate()],
        "reason" => "Prepare a bounded advisory review plan"
      },
      overrides
    )
  end

  defp step(id, action, depends_on \\ []) do
    %{
      "id" => id,
      "action" => action,
      "title" => "Review step #{id}",
      "depends_on" => depends_on
    }
  end

  defp decision_attrs(plan, overrides \\ %{}) do
    Map.merge(
      %{
        "task_id" => plan["review_task_id"],
        "decision" => "approve",
        "reason" => "Plan is bounded and suitable for advisory use"
      },
      overrides
    )
  end

  defp propose(attrs, context) do
    {:ok, plan, :executed} = Public.propose_plan(attrs, context, Ecto.UUID.generate())
    plan
  end

  defp counts(context) do
    %{
      plans: tenant_count(AgentPlanRecord, context),
      tasks: tenant_count(HumanTaskRecord, context),
      commands: tenant_count(CommandReceipt, context),
      audits: tenant_count(AuditEvent, context),
      events: tenant_count(OutboxEvent, context),
      connector_receipts: tenant_count(ConnectorReceiptRecord, context)
    }
  end

  defp tenant_count(schema, context) do
    TenantTransaction.run(context, fn ->
      Repo.aggregate(
        from(record in schema, where: record.tenant_id == ^context.tenant_id),
        :count
      )
    end)
  end

  defp tenant_all(schema, context) do
    TenantTransaction.run(context, fn ->
      Repo.all(from(record in schema, where: record.tenant_id == ^context.tenant_id))
    end)
  end
end
