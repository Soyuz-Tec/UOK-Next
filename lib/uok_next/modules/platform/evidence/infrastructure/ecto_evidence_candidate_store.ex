defmodule UokNext.Modules.Platform.Evidence.Infrastructure.EctoEvidenceCandidateStore do
  @moduledoc false

  @behaviour UokNext.Modules.Platform.Evidence.Application.EvidenceCandidateStore

  import Ecto.Query

  alias UokNext.Modules.Platform.Evidence.Infrastructure.EvidenceCandidateRecord
  alias UokNext.Repo

  @impl true
  def create(attrs, _context) do
    %EvidenceCandidateRecord{}
    |> EvidenceCandidateRecord.create_changeset(attrs)
    |> Repo.insert()
    |> normalize_write()
  end

  @impl true
  def fetch(id, tenant_id, _context),
    do: base_query(id, tenant_id) |> Repo.one() |> normalize_fetch()

  @impl true
  def fetch_for_update(id, tenant_id, _context) do
    id |> base_query(tenant_id) |> lock("FOR UPDATE") |> Repo.one() |> normalize_fetch()
  end

  @impl true
  def verify(record, attrs, _context) do
    record
    |> EvidenceCandidateRecord.verification_changeset(attrs)
    |> Repo.update(stale_error_field: :lock_version, stale_error_message: "is stale")
    |> normalize_update()
  end

  @impl true
  def list_for_subject(tenant_id, subject_type, subject_id, _context) do
    from(candidate in EvidenceCandidateRecord,
      where:
        candidate.tenant_id == ^tenant_id and candidate.subject_type == ^subject_type and
          candidate.subject_id == ^subject_id,
      order_by: [desc: candidate.inserted_at],
      limit: 20
    )
    |> Repo.all()
  end

  defp base_query(id, tenant_id) do
    from candidate in EvidenceCandidateRecord,
      where: candidate.id == ^id and candidate.tenant_id == ^tenant_id
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
