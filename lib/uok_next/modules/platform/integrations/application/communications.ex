defmodule UokNext.Modules.Platform.Integrations.Application.Communications do
  @moduledoc false
  alias UokNext.Kernel.{CommandError, CommandTransaction}
  alias UokNext.Modules.Platform.Integrations.Application.CommunicationAccess, as: Access
  alias UokNext.Modules.Platform.Integrations.Domain.CommunicationContract
  alias UokNext.Modules.Platform.Integrations.Policies.Authorization

  @spec link(map(), map(), map(), String.t()) :: tuple()
  def link(ports, attrs, context, key) do
    with :ok <- Authorization.require_permission(context, "communications:link"),
         {:ok, command} <- Access.validate(CommunicationContract.link(attrs)),
         {:ok, id} <- link_id(context, key),
         link = Map.put(command, :id, id),
         :ok <- Access.subject(link, context),
         {:ok, envelope} <- Access.envelope(link, context, "link", "link:" <> id),
         :ok <- Access.authorize(ports, envelope) do
      CommandTransaction.execute(
        context,
        "platform.integrations.link_communication",
        key,
        command,
        fn -> persist(ports, link, context) end
      )
    end
  end

  @spec get(map(), String.t(), map()) :: tuple()
  def get(ports, id, context) do
    with :ok <- Authorization.require_permission(context, "communications:read"),
         {:ok, link} <- Access.link(ports, id, context),
         :ok <- Access.subject(link, context),
         {:ok, envelope} <- Access.envelope(link, context, "link", "link:" <> link.id),
         :ok <- Access.authorize(ports, envelope) do
      {:ok, view(link)}
    end
  end

  @spec health(map(), map()) :: tuple()
  def health(ports, context) do
    with :ok <- Authorization.require_permission(context, "communications:read") do
      case ports.adapter.health() do
        {:ok, status} ->
          {:ok, Map.put(status, "external_delivery_state", "unverified")}

        {:error, _} ->
          {:ok,
           %{
             "status" => "unavailable",
             "contract_version" => 1,
             "system_role" => "communications_system",
             "external_delivery_state" => "unverified"
           }}
      end
    end
  end

  defp persist(ports, command, context) do
    attrs =
      command
      |> Map.drop([:reason])
      |> Map.merge(%{
        tenant_id: context.tenant_id,
        created_by_actor_id: context.actor_id
      })

    with :ok <- Access.subject(command, context),
         {:ok, link} <- Access.validate(ports.links.create(attrs, context)) do
      {:ok, view(link), audit(link, command.reason), [event(link)]}
    end
  end

  defp view(link) do
    %{
      "id" => link.id,
      "tenant_id" => link.tenant_id,
      "subject_type" => link.subject_type,
      "subject_id" => link.subject_id,
      "subject_version" => link.subject_version,
      "conversation_id" => link.conversation_id,
      "lock_version" => link.lock_version,
      "contract_version" => 1,
      "system_role" => "communications_system",
      "external_delivery_state" => "unverified"
    }
  end

  defp audit(link, reason) do
    %{
      action: "platform.integrations.link_communication",
      resource_type: "communication_link",
      resource_id: link.id,
      reason: reason,
      classification: "internal",
      metadata: %{"subject_type" => "party", "subject_version" => link.subject_version}
    }
  end

  defp event(link) do
    %{
      name: "platform.integrations.communication_linked",
      aggregate_type: "communication_link",
      aggregate_id: link.id,
      aggregate_version: link.lock_version,
      classification: "internal",
      payload: %{
        "communication_link_id" => link.id,
        "subject_type" => "party",
        "subject_id" => link.subject_id,
        "subject_version" => link.subject_version
      }
    }
  end

  # Stable opaque identity is necessary to independently authorize before a replay.
  defp link_id(context, key) when is_binary(key) and byte_size(key) in 8..128 do
    if Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$/, key) do
      <<a::32, b::16, _::4, c::12, _::2, d::62, _::binary>> =
        :crypto.hash(:sha256, Enum.join([context.tenant_id, context.actor_id, key], ":"))

      {:ok, Ecto.UUID.load!(<<a::32, b::16, 8::4, c::12, 2::2, d::62>>)}
    else
      invalid_key()
    end
  end

  defp link_id(_context, _key), do: invalid_key()

  defp invalid_key,
    do:
      {:error,
       CommandError.new(
         "invalid_idempotency_key",
         "idempotency key must contain 8 to 128 safe characters",
         400
       )}
end
