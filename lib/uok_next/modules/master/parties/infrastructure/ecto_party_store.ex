defmodule UokNext.Modules.Master.Parties.Infrastructure.EctoPartyStore do
  @moduledoc false

  @behaviour UokNext.Modules.Master.Parties.Application.PartyStore

  import Ecto.Query

  alias UokNext.Modules.Master.Parties.Infrastructure.PartyRecord
  alias UokNext.Repo

  @impl true
  def create(attrs, _context) do
    %PartyRecord{}
    |> PartyRecord.create_changeset(attrs)
    |> Repo.insert()
    |> normalize_write()
  end

  @impl true
  def fetch(id, tenant_id, _context),
    do: fetch_query(id, tenant_id) |> Repo.one() |> normalize_fetch()

  @impl true
  def fetch_for_update(id, tenant_id, _context) do
    id
    |> fetch_query(tenant_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> normalize_fetch()
  end

  @impl true
  def list(tenant_id, limit, _context) do
    from(party in PartyRecord,
      where: party.tenant_id == ^tenant_id,
      order_by: [desc: party.inserted_at, desc: party.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  @impl true
  def update(record, _action, attrs, _context) do
    record
    |> PartyRecord.transition_changeset(attrs)
    |> Repo.update(stale_error_field: :lock_version, stale_error_message: "is stale")
    |> normalize_update()
  end

  defp fetch_query(id, tenant_id) do
    from party in PartyRecord,
      where: party.id == ^id and party.tenant_id == ^tenant_id
  end

  defp normalize_fetch(nil), do: :not_found
  defp normalize_fetch(record), do: {:ok, record}

  defp normalize_write({:ok, record}), do: {:ok, record}
  defp normalize_write({:error, changeset}), do: {:error, changeset_errors(changeset)}

  defp normalize_update({:ok, record}), do: {:ok, record}

  defp normalize_update({:error, changeset}) do
    if Keyword.has_key?(changeset.errors, :lock_version) do
      {:error, :stale}
    else
      {:error, changeset_errors(changeset)}
    end
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, rendered ->
        String.replace(rendered, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
