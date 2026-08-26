defmodule UokNext.Modules.Platform.Evidence.Application.OperationalLineage do
  @moduledoc false

  alias UokNext.Kernel.{CommandError, TenantTransaction}
  alias UokNext.Modules.Platform.Evidence.Policies.Authorization

  @permission "evidence:read"
  @type_pattern ~r/\A[a-z][a-z0-9_]{1,119}\z/
  @maximum_refs 20
  @maximum_rows 100

  @spec get(module(), [map()], term()) :: {:ok, map()} | {:error, CommandError.t()}
  def get(store, refs, context) do
    with :ok <- Authorization.require_permission(context, @permission),
         {:ok, normalized} <- normalize_refs(refs) do
      TenantTransaction.run(context, fn ->
        {:ok, store.fetch(normalized, context.tenant_id, @maximum_rows, context)}
      end)
    end
  end

  defp normalize_refs(refs) when is_list(refs) and length(refs) in 1..@maximum_refs do
    refs
    |> Enum.reduce_while({:ok, []}, fn ref, {:ok, normalized} ->
      case normalize_ref(ref) do
        {:ok, item} -> {:cont, {:ok, [item | normalized]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, normalized |> Enum.uniq() |> Enum.sort()}
      :error -> invalid_refs()
    end
  end

  defp normalize_refs(_refs), do: invalid_refs()

  defp normalize_ref(ref) when is_map(ref) do
    type = Map.get(ref, :type, Map.get(ref, "type"))
    id = Map.get(ref, :id, Map.get(ref, "id"))

    with true <- is_binary(type) and Regex.match?(@type_pattern, type),
         {:ok, canonical_id} <- Ecto.UUID.cast(id) do
      {:ok, %{type: type, id: canonical_id}}
    else
      _invalid -> :error
    end
  end

  defp normalize_ref(_ref), do: :error

  defp invalid_refs do
    {:error,
     CommandError.new(
       "validation_failed",
       "operational lineage validation failed",
       422,
       %{references: ["must contain 1 to 20 typed UUID references"]}
     )}
  end
end
