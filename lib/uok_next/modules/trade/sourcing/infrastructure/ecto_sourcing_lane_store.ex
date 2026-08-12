defmodule UokNext.Modules.Trade.Sourcing.Infrastructure.EctoSourcingLaneStore do
  @moduledoc false

  @behaviour UokNext.Modules.Trade.Sourcing.Application.SourcingLaneStore

  import Ecto.Query

  alias UokNext.Modules.Trade.Sourcing.Infrastructure.SourcingLaneRecord
  alias UokNext.Repo

  @impl true
  def create(attrs, _context) do
    %SourcingLaneRecord{}
    |> SourcingLaneRecord.create_changeset(attrs)
    |> Repo.insert()
    |> normalize_write()
  end

  @impl true
  def fetch(id, tenant_id, _context),
    do: fetch_query(id, tenant_id) |> Repo.one() |> normalize_fetch()

  @impl true
  def fetch_for_update(id, tenant_id, _context) do
    id |> fetch_query(tenant_id) |> lock("FOR UPDATE") |> Repo.one() |> normalize_fetch()
  end

  @impl true
  def list(tenant_id, limit, _context) do
    from(lane in SourcingLaneRecord,
      where: lane.tenant_id == ^tenant_id,
      order_by: [desc: lane.inserted_at, desc: lane.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  @impl true
  def update(record, attrs, _context) do
    record
    |> SourcingLaneRecord.transition_changeset(attrs)
    |> Repo.update(stale_error_field: :lock_version, stale_error_message: "is stale")
    |> normalize_update()
  end

  defp fetch_query(id, tenant_id) do
    from lane in SourcingLaneRecord,
      where: lane.id == ^id and lane.tenant_id == ^tenant_id
  end

  defp normalize_fetch(nil), do: :not_found
  defp normalize_fetch(record), do: {:ok, record}
  defp normalize_write({:ok, record}), do: {:ok, record}
  defp normalize_write({:error, changeset}), do: {:error, changeset_errors(changeset)}
  defp normalize_update({:ok, record}), do: {:ok, record}

  defp normalize_update({:error, changeset}) do
    if Keyword.has_key?(changeset.errors, :lock_version),
      do: {:error, :stale},
      else: {:error, changeset_errors(changeset)}
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, rendered ->
        String.replace(rendered, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
