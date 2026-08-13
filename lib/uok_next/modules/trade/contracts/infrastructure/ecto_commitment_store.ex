defmodule UokNext.Modules.Trade.Contracts.Infrastructure.EctoCommitmentStore do
  @moduledoc false

  @behaviour UokNext.Modules.Trade.Contracts.Application.CommitmentStore

  import Ecto.Query

  alias UokNext.Modules.Trade.Contracts.Infrastructure.PurchaseCommitmentProposalRecord
  alias UokNext.Repo

  def create(attrs, _context) do
    %PurchaseCommitmentProposalRecord{}
    |> PurchaseCommitmentProposalRecord.create_changeset(attrs)
    |> Repo.insert()
    |> normalize_write()
  end

  def fetch(id, tenant_id, _context, options) do
    query =
      from proposal in PurchaseCommitmentProposalRecord,
        where: proposal.id == ^id and proposal.tenant_id == ^tenant_id

    query = if Keyword.get(options, :lock, false), do: lock(query, "FOR UPDATE"), else: query
    query |> Repo.one() |> normalize_fetch()
  end

  def list(tenant_id, limit, _context) do
    from(proposal in PurchaseCommitmentProposalRecord,
      where: proposal.tenant_id == ^tenant_id,
      order_by: [desc: proposal.inserted_at, desc: proposal.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  def update(record, attrs, _context) do
    record
    |> PurchaseCommitmentProposalRecord.transition_changeset(attrs)
    |> Repo.update(stale_error_field: :lock_version, stale_error_message: "is stale")
    |> normalize_update()
  end

  defp normalize_fetch(nil), do: :not_found
  defp normalize_fetch(record), do: {:ok, record}
  defp normalize_write({:ok, record}), do: {:ok, record}
  defp normalize_write({:error, changeset}), do: {:error, errors(changeset)}
  defp normalize_update({:ok, record}), do: {:ok, record}

  defp normalize_update({:error, changeset}) do
    if Keyword.has_key?(changeset.errors, :lock_version),
      do: {:error, :stale},
      else: {:error, errors(changeset)}
  end

  defp errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, rendered ->
        String.replace(rendered, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
