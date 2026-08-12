defmodule UokNext.Modules.Platform.Workflow.Infrastructure.EctoHumanTaskStore do
  @moduledoc false

  @behaviour UokNext.Modules.Platform.Workflow.Application.HumanTaskStore

  import Ecto.Query

  alias UokNext.Modules.Platform.Workflow.Infrastructure.HumanTaskRecord
  alias UokNext.Repo

  @impl true
  def create(attrs, _context) do
    %HumanTaskRecord{}
    |> HumanTaskRecord.create_changeset(attrs)
    |> Repo.insert()
    |> normalize_write()
  end

  @impl true
  def fetch_for_update(id, tenant_id, _context) do
    from(task in HumanTaskRecord,
      where: task.id == ^id and task.tenant_id == ^tenant_id,
      lock: "FOR UPDATE"
    )
    |> Repo.one()
    |> normalize_fetch()
  end

  @impl true
  def complete(record, attrs, _context) do
    record
    |> HumanTaskRecord.completion_changeset(attrs)
    |> Repo.update(stale_error_field: :lock_version, stale_error_message: "is stale")
    |> normalize_update()
  end

  @impl true
  def list_open(tenant_id, permissions, _context) do
    from(task in HumanTaskRecord,
      where:
        task.tenant_id == ^tenant_id and task.status == "open" and
          task.required_permission in ^permissions,
      order_by: [asc: task.inserted_at, asc: task.id],
      limit: 100
    )
    |> Repo.all()
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
