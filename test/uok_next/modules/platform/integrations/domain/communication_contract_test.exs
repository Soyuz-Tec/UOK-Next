defmodule UokNext.Modules.Platform.Integrations.Domain.CommunicationContractTest do
  use ExUnit.Case, async: false

  alias UokNext.CommunicationsContractDouble, as: Double
  alias UokNext.Modules.Platform.Integrations.Domain.CommunicationContract, as: Contract
  alias UokNext.Modules.Platform.Integrations.Infrastructure.CommunicationsAdapter, as: Adapter

  defmodule ExitingAdapter do
    def health, do: Process.exit(self(), :kill)
  end

  defmodule BlockingAdapter do
    def health do
      receive do
        :never_sent -> {:error, :unavailable}
      end
    end
  end

  defmodule ObservedBlockingAdapter do
    def health do
      send(Application.fetch_env!(:uok_next, :communications_test_observer), {:callback, self()})

      receive do
        :never_sent -> {:error, :unavailable}
      end
    end
  end

  setup do
    previous = Application.fetch_env(:uok_next, :communications_adapter)
    start_supervised!(Double)
    Application.put_env(:uok_next, :communications_adapter, Double)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:uok_next, :communications_adapter, value)
        :error -> Application.delete_env(:uok_next, :communications_adapter)
      end
    end)

    {:ok, envelope} = Contract.envelope(envelope_attrs())
    %{envelope: envelope}
  end

  test "link input is exact, typed, content-free and normalized" do
    attrs = link_attrs() |> Map.put("reason", "  Discuss this party  ")
    assert {:ok, link} = Contract.link(attrs)
    assert link.subject_type == "party"
    assert link.reason == "Discuss this party"
    assert link.subject_version == 1

    for field <-
          ~w(body content metadata tenant_id actor_id permissions authorized url credential) do
      assert {:error, %{field: "command"}} = Contract.link(Map.put(attrs, field, "untrusted"))
    end

    assert {:error, _} =
             Contract.link(Map.new(attrs, fn {key, value} -> {String.to_atom(key), value} end))

    assert {:error, _} = Contract.link(Map.delete(attrs, "reason"))
    assert {:error, _} = Contract.link(Map.put(attrs, "subject_type", "shipment"))
    assert {:error, _} = Contract.link(Map.put(attrs, "subject_version", 0))
    assert {:error, _} = Contract.link(Map.put(attrs, "conversation_id", "not-a-conversation"))
    assert {:error, _} = Contract.link(Map.put(attrs, "reason", String.duplicate("x", 501)))
    assert {:error, _} = Contract.link(Map.put(attrs, "reason", <<255>>))
    assert {:error, _} = Contract.link(nil)
  end

  test "delivery input keeps retry lineage outside the stable intent envelope" do
    attrs = %{"delivery_key" => "delivery:001", "reason" => "Share object reference"}
    assert {:ok, %{previous_receipt_id: nil}} = Contract.delivery(attrs)
    receipt_id = Ecto.UUID.generate()

    assert {:ok, %{previous_receipt_id: ^receipt_id}} =
             Contract.delivery(Map.put(attrs, "previous_receipt_id", receipt_id))

    for changed <- [
          Map.put(attrs, "delivery_key", "short"),
          Map.put(attrs, "delivery_key", "https://example.invalid/"),
          Map.put(attrs, "delivery_key", String.duplicate("x", 129)),
          Map.put(attrs, "previous_receipt_id", "wrong"),
          Map.put(attrs, "body", "private"),
          Map.put(attrs, "reason", "")
        ] do
      assert {:error, _} = Contract.delivery(changed)
    end
  end

  test "envelopes derive a digest over every exact scope field", %{envelope: envelope} do
    attrs = Map.delete(envelope, "request_sha256")
    assert {:ok, ^envelope} = Contract.envelope(attrs |> Enum.reverse() |> Map.new())
    assert {:ok, ^envelope} = Contract.validate_envelope(envelope)
    assert byte_size(envelope["request_sha256"]) == 64
    assert {:error, _} = Contract.envelope(envelope)
    assert {:error, _} = Contract.envelope(Map.put(attrs, "system_role", "another_system"))
    assert {:error, _} = Contract.envelope(Map.put(attrs, "contract_version", 2))
    assert {:error, _} = Contract.envelope(Map.put(attrs, "body", "private"))

    assert {:error, _} =
             Contract.validate_envelope(Map.put(envelope, "actor_id", Ecto.UUID.generate()))

    {:ok, changed} = Contract.envelope(Map.put(attrs, "subject_version", 2))
    refute changed["request_sha256"] == envelope["request_sha256"]
  end

  test "disabled integration is unavailable with no callback", %{envelope: envelope} do
    Application.put_env(:uok_next, :communications_adapter, :disabled)
    assert {:error, :unavailable} = Adapter.health()
    assert {:error, :unavailable} = Adapter.authorize(envelope)
    assert Double.calls() == %{}
  end

  test "independent scope and current revocation govern every operation", %{envelope: envelope} do
    assert {:error, :denied} = Adapter.authorize(envelope)
    Double.grant(envelope)
    assert {:ok, proof} = Adapter.authorize(envelope)
    assert proof["request_sha256"] == envelope["request_sha256"]

    for field <- ~w(tenant_id actor_id conversation_id) do
      attrs = envelope |> Map.delete("request_sha256") |> Map.put(field, Ecto.UUID.generate())
      assert {:ok, foreign} = Contract.envelope(attrs)
      assert {:error, :denied} = Adapter.authorize(foreign)
    end

    Double.revoke(envelope)
    assert {:error, :denied} = Adapter.authorize(envelope)
    assert {:error, :denied} = Adapter.deliver(envelope)
    assert Double.deliveries() == %{}
  end

  test "expired, substituted or content-bearing authorization proofs fail closed", %{
    envelope: envelope
  } do
    Double.grant(envelope)

    for mode <- [:expired, :substitution, :malformed] do
      Double.mode(:authorize, mode)
      assert {:error, :invalid_response} = Adapter.authorize(envelope)
      assert {:error, :invalid_response} = Adapter.deliver(envelope)
    end

    assert Double.deliveries() == %{}
  end

  test "handoff is idempotent and accepted is not a delivery or read claim", %{envelope: envelope} do
    Double.grant(envelope)
    assert {:ok, receipt} = Adapter.deliver(envelope)
    assert {:ok, ^receipt} = Adapter.deliver(envelope)
    assert {:ok, ^receipt} = Adapter.reconcile(envelope)
    assert receipt["acceptance"] == "contract_accepted"

    assert Map.keys(receipt) |> Enum.sort() ==
             ~w(acceptance contract_version receipt_id request_sha256 system_role)

    assert map_size(Double.deliveries()) == 1

    attrs = envelope |> Map.delete("request_sha256") |> Map.put("subject_version", 2)
    {:ok, changed} = Contract.envelope(attrs)
    assert {:error, :conflict} = Adapter.deliver(changed)
    assert map_size(Double.deliveries()) == 1

    Double.revoke(envelope)
    assert {:error, :denied} = Adapter.reconcile(envelope)
    assert {:error, :denied} = Adapter.deliver(envelope)
  end

  test "lost response reconciles the single accepted handoff", %{envelope: envelope} do
    Double.grant(envelope)
    assert {:error, :not_found} = Adapter.reconcile(envelope)
    Double.mode(:deliver, :lost_response)
    assert {:error, :timed_out} = Adapter.deliver(envelope)
    assert map_size(Double.deliveries()) == 1
    assert {:ok, receipt} = Adapter.reconcile(envelope)
    Double.mode(:deliver, :available)
    assert {:ok, ^receipt} = Adapter.deliver(envelope)
    assert map_size(Double.deliveries()) == 1
  end

  test "bounded receipt and health failures never fabricate acceptance", %{envelope: envelope} do
    Double.grant(envelope)
    assert {:ok, %{"status" => "local_contract_double"}} = Adapter.health()

    for mode <- [:malformed, :substitution] do
      Double.mode(:deliver, mode)
      assert {:error, :invalid_response} = Adapter.deliver(envelope)
    end

    for mode <- [:unavailable, :timed_out] do
      Double.mode(mode)
      assert {:error, ^mode} = Adapter.health()
      assert {:error, ^mode} = Adapter.authorize(envelope)
    end

    assert Double.deliveries() == %{}
  end

  test "hard adapter exits are contained and cannot kill the request process" do
    Application.put_env(:uok_next, :communications_adapter, ExitingAdapter)
    assert {:error, :unavailable} = Adapter.health()
    assert Process.alive?(self())
  end

  test "a blocked callback has a bounded deadline" do
    Application.put_env(:uok_next, :communications_adapter, BlockingAdapter)
    started = System.monotonic_time(:millisecond)
    assert {:error, :timed_out} = Adapter.health()
    assert System.monotonic_time(:millisecond) - started < 2_000
  end

  test "request cancellation terminates an outstanding adapter callback" do
    Application.put_env(:uok_next, :communications_adapter, ObservedBlockingAdapter)
    Application.put_env(:uok_next, :communications_test_observer, self())
    on_exit(fn -> Application.delete_env(:uok_next, :communications_test_observer) end)
    caller = spawn(fn -> Adapter.health() end)
    assert_receive {:callback, worker}
    monitor = Process.monitor(worker)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}, 500
  end

  test "expired server deadlines prevent handoff after authorization", %{envelope: envelope} do
    Double.grant(envelope)
    assert {:error, :timed_out} = Adapter.deliver(envelope, DateTime.add(DateTime.utc_now(), -1))
    assert Double.deliveries() == %{}
    assert {:ok, _receipt} = Adapter.deliver(envelope, DateTime.add(DateTime.utc_now(), 30))
  end

  defp link_attrs do
    %{
      "subject_type" => "party",
      "subject_id" => Ecto.UUID.generate(),
      "subject_version" => 1,
      "conversation_id" => Ecto.UUID.generate(),
      "reason" => "Discuss this party"
    }
  end

  defp envelope_attrs do
    %{
      "contract_version" => 1,
      "system_role" => "communications_system",
      "tenant_id" => Ecto.UUID.generate(),
      "actor_id" => Ecto.UUID.generate(),
      "subject_type" => "party",
      "subject_id" => Ecto.UUID.generate(),
      "subject_version" => 1,
      "conversation_id" => Ecto.UUID.generate(),
      "link_id" => Ecto.UUID.generate(),
      "operation" => "delivery",
      "delivery_key" => "delivery:001"
    }
  end
end
