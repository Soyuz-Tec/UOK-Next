defmodule UokNext.Modules.Platform.Integrations.Infrastructure.CommunicationsAdapter do
  @moduledoc """
  Fail-closed, content-free boundary for the local communications contract.

  The implementation is selected exclusively by trusted application configuration.
  The default is disabled. No endpoint, credential or grant is accepted from callers.
  Acceptance proves only a contract handoff; it is never a message-delivery claim.
  """

  alias UokNext.Modules.Platform.Integrations.Domain.CommunicationContract

  @timeout_ms 1_000
  @errors ~w(unavailable timed_out denied not_found conflict)a
  @proof_fields ~w(contract_version system_role request_sha256 expires_at)
  @receipt_fields ~w(contract_version system_role request_sha256 receipt_id acceptance)

  @spec health() :: {:ok, map()} | {:error, atom()}
  def health do
    with {:ok, result} <- invoke(:health, []),
         :ok <- exact(result, ~w(status contract_version system_role)),
         :ok <- identity(result),
         true <- result["status"] == "local_contract_double" do
      {:ok, result}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_response}
    end
  end

  @spec authorize(map()) :: {:ok, map()} | {:error, atom()}
  def authorize(envelope) do
    with {:ok, envelope} <- valid_envelope(envelope),
         {:ok, result} <- invoke(:authorize, [envelope]),
         :ok <- exact(result, @proof_fields),
         :ok <- bound_response(result, envelope),
         :ok <- fresh(result["expires_at"]) do
      {:ok, result}
    end
  end

  @spec deliver(map()) :: {:ok, map()} | {:error, atom()}
  def deliver(envelope), do: handoff(:deliver, envelope)

  @spec deliver(map(), DateTime.t()) :: {:ok, map()} | {:error, atom()}
  def deliver(envelope, %DateTime{} = deadline_at), do: handoff(:deliver, envelope, deadline_at)
  def deliver(_envelope, _deadline_at), do: {:error, :timed_out}

  @spec reconcile(map()) :: {:ok, map()} | {:error, atom()}
  def reconcile(envelope), do: handoff(:reconcile, envelope)

  defp handoff(operation, envelope, deadline_at \\ nil) do
    with {:ok, envelope} <- valid_envelope(envelope),
         true <- envelope["operation"] == "delivery",
         {:ok, _proof} <- authorize(envelope),
         :ok <- before_deadline(deadline_at),
         {:ok, result} <- invoke(operation, [envelope]),
         :ok <- exact(result, @receipt_fields),
         :ok <- bound_response(result, envelope),
         {:ok, receipt_id} <- CommunicationContract.uuid(result["receipt_id"], "receipt_id"),
         true <- receipt_id == result["receipt_id"],
         true <- result["acceptance"] == "contract_accepted" do
      {:ok, result}
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :invalid_response}
    end
  end

  defp invoke(operation, arguments) do
    case Application.get_env(:uok_next, :communications_adapter) do
      adapter when is_atom(adapter) and adapter not in [nil, :disabled, __MODULE__] ->
        bounded_invoke(adapter, operation, arguments)

      _ ->
        {:error, :unavailable}
    end
  end

  defp bounded_invoke(adapter, operation, arguments) do
    reply = :erlang.alias()
    caller = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        response = guarded_invoke(caller, adapter, operation, arguments)
        send(reply, {reply, response})
      end)

    try do
      receive do
        {^reply, response} -> bounded_result(response)
        {:DOWN, ^monitor, :process, ^pid, _reason} -> {:error, :unavailable}
      after
        @timeout_ms ->
          Process.exit(pid, :kill)
          {:error, :timed_out}
      end
    after
      :erlang.unalias(reply)
      Process.demonitor(monitor, [:flush])
    end
  end

  defp guarded_invoke(caller, adapter, operation, arguments) do
    Process.flag(:trap_exit, true)
    caller_monitor = Process.monitor(caller)
    coordinator = self()
    response_ref = make_ref()

    worker =
      spawn_link(fn ->
        send(coordinator, {response_ref, safe_invoke(adapter, operation, arguments)})
      end)

    try do
      receive do
        {^response_ref, response} -> response
        {:EXIT, ^worker, _reason} -> {:error, :unavailable}
        {:DOWN, ^caller_monitor, :process, ^caller, _reason} -> {:error, :unavailable}
      after
        @timeout_ms -> {:error, :timed_out}
      end
    after
      Process.exit(worker, :kill)
      Process.demonitor(caller_monitor, [:flush])
    end
  end

  defp before_deadline(nil), do: :ok

  defp before_deadline(%DateTime{} = deadline_at) do
    if DateTime.compare(deadline_at, DateTime.utc_now()) == :gt,
      do: :ok,
      else: {:error, :timed_out}
  end

  defp before_deadline(_deadline_at), do: {:error, :timed_out}

  defp bounded_result({:ok, result}) when is_map(result), do: {:ok, result}
  defp bounded_result({:error, reason}) when reason in @errors, do: {:error, reason}
  defp bounded_result(_response), do: {:error, :invalid_response}

  defp safe_invoke(adapter, operation, arguments) do
    apply(adapter, operation, arguments)
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  defp bound_response(result, envelope) do
    with :ok <- identity(result),
         true <- result["request_sha256"] == envelope["request_sha256"] do
      :ok
    else
      _ -> {:error, :invalid_response}
    end
  end

  defp identity(%{"contract_version" => 1, "system_role" => "communications_system"}), do: :ok
  defp identity(_result), do: {:error, :invalid_response}

  defp fresh(value) when is_binary(value) and byte_size(value) <= 32 do
    now = DateTime.utc_now()

    with true <- String.valid?(value),
         {:ok, expires_at, 0} <- DateTime.from_iso8601(value),
         true <- DateTime.compare(expires_at, now) == :gt,
         true <- DateTime.diff(expires_at, now, :millisecond) <= 60_000 do
      :ok
    else
      _ -> {:error, :invalid_response}
    end
  end

  defp fresh(_value), do: {:error, :invalid_response}

  defp exact(result, fields) do
    case CommunicationContract.exact_keys(result, fields) do
      :ok -> :ok
      _ -> {:error, :invalid_response}
    end
  end

  defp valid_envelope(envelope) do
    case CommunicationContract.validate_envelope(envelope) do
      {:ok, canonical} -> {:ok, canonical}
      _ -> {:error, :invalid_response}
    end
  end
end
