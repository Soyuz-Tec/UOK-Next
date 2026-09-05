defmodule UokNext.Modules.Platform.Integrations.Application.CommunicationDeliveries do
  @moduledoc false
  alias UokNext.Kernel.{CommandError, TenantTransaction}
  alias UokNext.Modules.Platform.Integrations.Application.{CommunicationAccess, ConnectorReceipts}
  alias UokNext.Modules.Platform.Integrations.Domain.{CommunicationContract, ConnectorReceipt}
  alias UokNext.Modules.Platform.Integrations.Policies.Authorization

  @spec request(map(), String.t(), map(), integer(), map(), String.t()) :: tuple()
  def request(ports, link_id, attrs, expected_version, context, key) do
    with :ok <- Authorization.require_permission(context, "communications:deliver"),
         :ok <- outside_transaction(ports),
         {:ok, command} <- CommunicationAccess.validate(CommunicationContract.delivery(attrs)),
         {:ok, link} <- CommunicationAccess.link(ports, link_id, context),
         :ok <- CommunicationAccess.version(link.lock_version, expected_version),
         {:ok, envelope} <- preflight(ports, link, context, command.delivery_key),
         {:ok, attempt, disposition} <-
           begin_attempt(ports, link, command, envelope, context, key),
         {:ok, receipt} <- fetch_receipt(ports, attempt["id"], context),
         :ok <- receipt_binding(receipt, envelope) do
      finish_request(ports, link, receipt, envelope, context, disposition)
    end
  end

  @spec reconcile(map(), String.t(), String.t(), integer(), map(), String.t()) :: tuple()
  def reconcile(ports, link_id, receipt_id, expected_version, context, key) do
    with :ok <- Authorization.require_permission(context, "communications:reconcile"),
         {:ok, link} <- CommunicationAccess.link(ports, link_id, context),
         {:ok, receipt} <- fetch_receipt(ports, receipt_id, context),
         {:ok, envelope} <- preflight(ports, link, context, receipt.delivery_key),
         :ok <- receipt_binding(receipt, envelope),
         {:ok, outcome} <- reconciliation_outcome(ports, receipt, envelope),
         {:ok, result, disposition} <-
           complete(ports, receipt.id, expected_version, outcome, context, key, :reconciliation) do
      {:ok, view(result, link.id), disposition}
    end
  end

  defp outside_transaction(ports) do
    if ports.receipts.transaction_open?(),
      do:
        {:error,
         CommandError.new(
           "transaction_not_supported",
           "delivery must begin outside an existing transaction",
           409
         )},
      else: :ok
  end

  defp preflight(ports, link, context, delivery_key) do
    with :ok <- CommunicationAccess.subject(link, context),
         {:ok, envelope} <- CommunicationAccess.envelope(link, context, "delivery", delivery_key),
         :ok <- CommunicationAccess.authorize(ports, envelope) do
      {:ok, envelope}
    end
  end

  defp begin_attempt(ports, link, command, envelope, context, key) do
    attrs = %{
      connector_role: "communications_system",
      operation: "communications.delivery",
      delivery_key: command.delivery_key,
      request_sha256: envelope["request_sha256"],
      subject_type: "party",
      subject_id: link.subject_id,
      subject_version: link.subject_version,
      timeout_ms: 30_000,
      previous_receipt_id: command.previous_receipt_id,
      reason: command.reason
    }

    ConnectorReceipts.begin_communication_attempt(ports.receipts, attrs, context, key)
  end

  # Replaying the durable request never opens transport a second time. A lost
  # acknowledgement is recovered by the separately authorized reconciliation query.
  defp finish_request(_ports, link, receipt, _envelope, _context, :replayed),
    do: {:ok, view(ConnectorReceipts.view(receipt), link.id), :replayed}

  defp finish_request(ports, link, receipt, envelope, context, :executed) do
    with :ok <- CommunicationAccess.subject(link, context),
         {:ok, receipt} <- fetch_receipt(ports, receipt.id, context),
         :ok <- dispatchable(receipt) do
      case ports.adapter.deliver(envelope, receipt.deadline_at) do
        {:ok, acknowledgement} -> acknowledge(ports, link, receipt, acknowledgement, context)
        {:error, :denied} -> CommunicationAccess.adapter_error(:denied)
        {:error, _reason} -> {:ok, view(ConnectorReceipts.view(receipt), link.id), :executed}
      end
    end
  end

  defp acknowledge(ports, link, receipt, acknowledgement, context) do
    outcome =
      if expired?(receipt), do: timeout_outcome(), else: acceptance_outcome(acknowledgement)

    key = "communications-accept:" <> receipt.id

    with {:ok, result, _} <-
           complete(ports, receipt.id, receipt.lock_version, outcome, context, key, :delivery) do
      {:ok, view(result, link.id), :executed}
    end
  end

  defp reconciliation_outcome(ports, %{status: "attempted"} = receipt, envelope) do
    if expired?(receipt) do
      {:ok, timeout_outcome()}
    else
      case ports.adapter.reconcile(envelope) do
        {:ok, acknowledgement} -> {:ok, acceptance_outcome(acknowledgement)}
        {:error, reason} -> CommunicationAccess.adapter_error(reason)
      end
    end
  end

  defp reconciliation_outcome(_ports, %{status: "succeeded"} = receipt, _envelope) do
    {:ok,
     %{
       "status" => "succeeded",
       "response_sha256" => receipt.response_sha256,
       "external_reference" => receipt.external_reference,
       "reason" => "External system accepted the bounded contract only"
     }}
  end

  defp reconciliation_outcome(_ports, %{status: "timed_out"}, _envelope),
    do: {:ok, timeout_outcome()}

  defp reconciliation_outcome(_ports, _receipt, _envelope), do: CommunicationAccess.not_found()

  defp acceptance_outcome(acknowledgement) do
    digest =
      acknowledgement
      |> Enum.sort()
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    %{
      "status" => "succeeded",
      "response_sha256" => digest,
      "external_reference" => acknowledgement["receipt_id"],
      "reason" => "External system accepted the bounded contract only"
    }
  end

  defp timeout_outcome do
    %{
      "status" => "timed_out",
      "retry_after_seconds" => 0,
      "reason" => "Server deadline elapsed; remote delivery remains unverified"
    }
  end

  defp complete(ports, id, version, outcome, context, key, authority) do
    ConnectorReceipts.reconcile_communication_attempt(
      ports.receipts,
      id,
      version,
      outcome,
      context,
      key,
      authority
    )
  end

  defp fetch_receipt(ports, id, context) do
    with {:ok, id} <- CommunicationAccess.validate(ConnectorReceipt.validate_id(id)) do
      TenantTransaction.run(context, fn -> fetch_scoped_receipt(ports, id, context) end)
    end
  end

  defp fetch_scoped_receipt(ports, id, context) do
    case ports.receipts.fetch(id, context.tenant_id, context) do
      {:ok, receipt} -> {:ok, receipt}
      :not_found -> CommunicationAccess.not_found()
    end
  end

  defp receipt_binding(receipt, envelope) do
    if receipt.connector_role == "communications_system" and
         receipt.operation == "communications.delivery" and
         receipt.request_sha256 == envelope["request_sha256"] do
      :ok
    else
      CommunicationAccess.not_found()
    end
  end

  defp dispatchable(%{status: "attempted"} = receipt) do
    if expired?(receipt),
      do:
        {:error,
         CommandError.new("stale_state", "delivery deadline elapsed; reconcile the attempt", 409)},
      else: :ok
  end

  defp dispatchable(_receipt),
    do: {:error, CommandError.new("stale_state", "delivery attempt already reconciled", 409)}

  defp expired?(receipt), do: DateTime.compare(DateTime.utc_now(), receipt.deadline_at) != :lt

  defp view(receipt, link_id) do
    Map.merge(receipt, %{
      "communication_link_id" => link_id,
      "contract_acceptance" =>
        if(receipt["status"] == "succeeded", do: "contract_accepted", else: "pending"),
      "external_delivery_state" => "unverified"
    })
  end
end
