defmodule UokNext.Modules.Platform.Evidence.Infrastructure.EctoOperationalLineageStore do
  @moduledoc false

  @behaviour UokNext.Modules.Platform.Evidence.Application.OperationalLineageStore

  import Ecto.Query

  alias UokNext.Kernel.{AuditEvent, OutboxEvent}
  alias UokNext.Repo

  @statuses ~w(pending publishing published dead_letter)

  @impl true
  def fetch(refs, tenant_id, limit, _context) do
    audits = fetch_audits(refs, tenant_id, limit + 1)
    events = fetch_events(refs, tenant_id, limit + 1)
    audit_events = Enum.take(audits, limit)
    delivery_events = Enum.take(events, limit)

    %{
      "audit_events" => Enum.map(audit_events, &audit_view/1),
      "audit_events_truncated" => length(audits) > limit,
      "delivery_events" => Enum.map(delivery_events, &event_view/1),
      "delivery_events_truncated" => length(events) > limit,
      "delivery_status_counts" => status_counts(delivery_events)
    }
  end

  defp fetch_audits(refs, tenant_id, limit) do
    filter = audit_filter(refs)

    from(audit in AuditEvent,
      where: audit.tenant_id == ^tenant_id,
      where: ^filter,
      order_by: [asc: audit.occurred_at, asc: audit.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp fetch_events(refs, tenant_id, limit) do
    filter = event_filter(refs)

    from(event in OutboxEvent,
      where: event.tenant_id == ^tenant_id,
      where: ^filter,
      order_by: [asc: event.available_at, asc: event.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp audit_filter(refs) do
    Enum.reduce(refs, dynamic(false), fn ref, filter ->
      dynamic(
        [audit],
        ^filter or (audit.resource_type == ^ref.type and audit.resource_id == ^ref.id)
      )
    end)
  end

  defp event_filter(refs) do
    Enum.reduce(refs, dynamic(false), fn ref, filter ->
      dynamic(
        [event],
        ^filter or (event.aggregate_type == ^ref.type and event.aggregate_id == ^ref.id)
      )
    end)
  end

  defp audit_view(audit) do
    %{
      "id" => audit.id,
      "action" => audit.action,
      "resource_type" => audit.resource_type,
      "resource_id" => audit.resource_id,
      "outcome" => audit.outcome,
      "reason" => audit.reason,
      "classification" => audit.classification,
      "actor_id" => audit.actor_id,
      "correlation_id" => audit.correlation_id,
      "occurred_at" => DateTime.to_iso8601(audit.occurred_at)
    }
  end

  defp event_view(event) do
    %{
      "id" => event.id,
      "event_name" => event.event_name,
      "aggregate_type" => event.aggregate_type,
      "aggregate_id" => event.aggregate_id,
      "aggregate_version" => event.aggregate_version,
      "status" => event.status,
      "attempt_count" => event.attempt_count,
      "available_at" => DateTime.to_iso8601(event.available_at),
      "published_at" => iso8601(event.published_at)
    }
  end

  defp status_counts(events) do
    initial = Map.new(@statuses, &{&1, 0})
    Enum.reduce(events, initial, &Map.update!(&2, &1.status, fn count -> count + 1 end))
  end

  defp iso8601(nil), do: nil
  defp iso8601(datetime), do: DateTime.to_iso8601(datetime)
end
