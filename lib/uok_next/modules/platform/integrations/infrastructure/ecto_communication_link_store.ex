defmodule UokNext.Modules.Platform.Integrations.Infrastructure.EctoCommunicationLinkStore do
  @moduledoc false
  @behaviour UokNext.Modules.Platform.Integrations.Application.CommunicationLinkStore
  import Ecto.Query
  alias UokNext.Modules.Platform.Integrations.Infrastructure.CommunicationLinkRecord
  alias UokNext.Repo

  @impl true
  def create(attrs, _context) do
    case %CommunicationLinkRecord{}
         |> CommunicationLinkRecord.create_changeset(attrs)
         |> Repo.insert() do
      {:ok, link} ->
        {:ok, link}

      {:error, changeset} ->
        {:error, Ecto.Changeset.traverse_errors(changeset, fn {message, _} -> message end)}
    end
  end

  @impl true
  def fetch(id, tenant_id, _context) do
    case Repo.one(
           from(link in CommunicationLinkRecord,
             where: link.id == ^id and link.tenant_id == ^tenant_id
           )
         ) do
      nil -> :not_found
      link -> {:ok, link}
    end
  end
end
