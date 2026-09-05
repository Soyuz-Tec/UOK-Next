defmodule UokNext.Modules.Platform.Integrations.Application.CommunicationAccess do
  @moduledoc false
  alias UokNext.Kernel.{CommandError, TenantTransaction}
  alias UokNext.Modules.Master.Parties.Public, as: Parties
  alias UokNext.Modules.Platform.Integrations.Domain.{CommunicationContract, ConnectorReceipt}

  @spec link(map(), term(), map()) :: tuple()
  def link(ports, id, context) do
    with {:ok, id} <- validate(ConnectorReceipt.validate_id(id)) do
      TenantTransaction.run(context, fn -> fetch_link(ports, id, context) end)
    end
  end

  defp fetch_link(ports, id, context) do
    case ports.links.fetch(id, context.tenant_id, context) do
      {:ok, link} -> {:ok, link}
      :not_found -> not_found()
    end
  end

  @spec subject(map(), map()) :: tuple() | :ok
  def subject(link, context) do
    with {:ok, party} <- Parties.get(link.subject_id, context) do
      version(party["lock_version"], link.subject_version)
    end
  end

  @spec envelope(map(), map(), String.t(), String.t()) :: tuple()
  def envelope(link, context, operation, delivery_key) do
    CommunicationContract.envelope(%{
      "contract_version" => 1,
      "system_role" => "communications_system",
      "tenant_id" => context.tenant_id,
      "actor_id" => context.actor_id,
      "subject_type" => "party",
      "subject_id" => link.subject_id,
      "subject_version" => link.subject_version,
      "conversation_id" => link.conversation_id,
      "link_id" => link.id,
      "operation" => operation,
      "delivery_key" => delivery_key
    })
    |> validate()
  end

  @spec authorize(map(), map()) :: tuple() | :ok
  def authorize(ports, envelope) do
    case ports.adapter.authorize(envelope) do
      {:ok, _proof} -> :ok
      {:error, reason} -> adapter_error(reason)
    end
  end

  @spec version(term(), term()) :: :ok | tuple()
  def version(actual, expected) when is_integer(expected) and expected > 0 do
    if actual == expected,
      do: :ok,
      else:
        {:error, CommandError.new("stale_state", "communication subject or receipt changed", 409)}
  end

  def version(_actual, _expected), do: validation_error(%{expected_version: ["must be positive"]})

  @spec validate(tuple()) :: tuple()
  def validate({:ok, value}), do: {:ok, value}
  def validate({:error, details}), do: validation_error(details)

  @spec validation_error(map()) :: tuple()
  def validation_error(details),
    do:
      {:error,
       CommandError.new(
         "validation_failed",
         "communication contract validation failed",
         422,
         details
       )}

  @spec adapter_error(atom()) :: tuple()
  def adapter_error(:denied),
    do:
      {:error,
       CommandError.new("communications_denied", "external communication access is denied", 403)}

  def adapter_error(:invalid_response),
    do:
      {:error,
       CommandError.new(
         "communications_invalid_response",
         "external contract response is invalid",
         502
       )}

  def adapter_error(_reason),
    do:
      {:error,
       CommandError.new(
         "communications_unavailable",
         "communications contract is unavailable",
         503
       )}

  @spec not_found() :: tuple()
  def not_found, do: {:error, CommandError.new("not_found", "record was not found", 404)}
end
