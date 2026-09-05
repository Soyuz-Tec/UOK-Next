defmodule UokNext.CommunicationsContractDouble do
  @moduledoc "Independent local communications authority and idempotent handoff test double."
  @behaviour UokNext.Modules.Platform.Integrations.Application.CommunicationsPort

  use Agent

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_opts \\ []) do
    Agent.start_link(
      fn -> %{grants: MapSet.new(), modes: %{}, deliveries: %{}, calls: %{}} end,
      name: __MODULE__
    )
  end

  @spec grant(map()) :: :ok
  def grant(scope) do
    Agent.update(__MODULE__, fn state ->
      %{state | grants: Enum.reduce(scopes(scope), state.grants, &MapSet.put(&2, &1))}
    end)
  end

  @spec revoke(map()) :: :ok
  def revoke(scope) do
    Agent.update(__MODULE__, fn state ->
      %{state | grants: Enum.reduce(scopes(scope), state.grants, &MapSet.delete(&2, &1))}
    end)
  end

  @spec mode(atom()) :: :ok
  def mode(mode), do: mode(:all, mode)

  @spec mode(atom(), atom()) :: :ok
  def mode(operation, mode) do
    Agent.update(__MODULE__, &put_in(&1, [:modes, operation], mode))
  end

  @spec deliveries() :: map()
  def deliveries, do: Agent.get(__MODULE__, & &1.deliveries)

  @spec calls() :: map()
  def calls, do: Agent.get(__MODULE__, & &1.calls)

  @impl true
  def health do
    perform(:health, %{}, fn state ->
      {{:ok, Map.put(identity(), "status", "local_contract_double")}, state}
    end)
  end

  @impl true
  def authorize(envelope) do
    perform(:authorize, envelope, fn state ->
      if authorized?(state, envelope) do
        proof =
          identity()
          |> Map.put("request_sha256", envelope["request_sha256"])
          |> Map.put(
            "expires_at",
            DateTime.utc_now() |> DateTime.add(30) |> DateTime.to_iso8601()
          )

        {{:ok, proof}, state}
      else
        {{:error, :denied}, state}
      end
    end)
  end

  @impl true
  def deliver(envelope), do: perform(:deliver, envelope, &handoff(&1, envelope, true))

  @impl true
  def reconcile(envelope), do: perform(:reconcile, envelope, &handoff(&1, envelope, false))

  defp perform(operation, envelope, callback) do
    Agent.get_and_update(__MODULE__, fn state ->
      state = update_in(state, [:calls, operation], &((&1 || 0) + 1))
      mode = Map.get(state.modes, operation, Map.get(state.modes, :all, :available))

      perform_mode(mode, {operation, envelope}, state, callback)
    end)
  end

  defp perform_mode(:available, _request, state, callback), do: callback.(state)

  defp perform_mode(:malformed, _request, state, _callback),
    do: {{:ok, %{"body" => "must never leave this double"}}, state}

  defp perform_mode(:substitution, {operation, envelope}, state, _callback),
    do: substituted(operation, envelope, state)

  defp perform_mode(:expired, {_operation, envelope}, state, _callback),
    do: expired(envelope, state)

  defp perform_mode(mode, _request, state, _callback)
       when mode in [:unavailable, :timed_out, :denied],
       do: {{:error, mode}, state}

  defp perform_mode(:lost_response, {operation, envelope}, state, _callback),
    do: lost_response(operation, envelope, state)

  defp perform_mode(:raise, _request, _state, _callback),
    do: raise("test-only adapter exception must not escape")

  defp lost_response(:deliver, envelope, state) do
    case handoff(state, envelope, true) do
      {{:ok, _receipt}, updated} -> {{:error, :timed_out}, updated}
      error -> error
    end
  end

  defp lost_response(_operation, _envelope, state), do: {{:error, :unavailable}, state}

  defp handoff(state, envelope, create?) do
    if authorized?(state, envelope) do
      key = {envelope["tenant_id"], envelope["delivery_key"]}
      reconcile_handoff(Map.get(state.deliveries, key), key, state, envelope, create?)
    else
      {{:error, :denied}, state}
    end
  end

  defp reconcile_handoff(nil, key, state, envelope, true) do
    receipt = receipt(envelope)
    {{:ok, receipt}, put_in(state, [:deliveries, key], receipt)}
  end

  defp reconcile_handoff(nil, _key, state, _envelope, false),
    do: {{:error, :not_found}, state}

  defp reconcile_handoff(receipt, _key, state, envelope, _create?) do
    if receipt["request_sha256"] == envelope["request_sha256"],
      do: {{:ok, receipt}, state},
      else: {{:error, :conflict}, state}
  end

  defp substituted(:authorize, envelope, state) do
    result =
      identity()
      |> Map.put("request_sha256", String.duplicate("0", 64))
      |> Map.put("expires_at", DateTime.utc_now() |> DateTime.add(30) |> DateTime.to_iso8601())

    {{:ok, Map.put(result, "request_sha256", substituted_digest(envelope))}, state}
  end

  defp substituted(_operation, envelope, state),
    do: {{:ok, Map.put(receipt(envelope), "request_sha256", substituted_digest(envelope))}, state}

  defp expired(envelope, state) do
    result =
      identity()
      |> Map.put("request_sha256", envelope["request_sha256"])
      |> Map.put("expires_at", DateTime.utc_now() |> DateTime.add(-1) |> DateTime.to_iso8601())

    {{:ok, result}, state}
  end

  defp receipt(envelope) do
    identity()
    |> Map.put("request_sha256", envelope["request_sha256"])
    |> Map.put("receipt_id", Ecto.UUID.generate())
    |> Map.put("acceptance", "contract_accepted")
  end

  defp identity, do: %{"contract_version" => 1, "system_role" => "communications_system"}

  defp substituted_digest(envelope) do
    if envelope["request_sha256"] == String.duplicate("0", 64),
      do: String.duplicate("1", 64),
      else: String.duplicate("0", 64)
  end

  defp authorized?(state, envelope), do: MapSet.member?(state.grants, scope(envelope))

  defp scopes(attrs) do
    operations =
      if value(attrs, :operation), do: [value(attrs, :operation)], else: ~w(link delivery)

    Enum.map(operations, fn operation ->
      {value(attrs, :tenant_id), value(attrs, :actor_id), value(attrs, :conversation_id),
       operation}
    end)
  end

  defp scope(attrs),
    do: {attrs["tenant_id"], attrs["actor_id"], attrs["conversation_id"], attrs["operation"]}

  defp value(attrs, field), do: Map.get(attrs, field, Map.get(attrs, Atom.to_string(field)))
end
