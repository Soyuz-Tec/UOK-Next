defmodule UokNext.Modules.Platform.Identity.Domain.AccessProfile do
  @moduledoc false

  @profiles %{
    "entity_onboarding_operator" => %{
      label: "Entity onboarding operator",
      permissions:
        ~w(evidence:read evidence:upload parties:create parties:evidence:submit parties:read)
    },
    "entity_onboarding_reviewer" => %{
      label: "Entity onboarding reviewer",
      permissions: ~w(
        evidence:read
        evidence:upload
        parties:approve
        parties:create
        parties:evidence:submit
        parties:read
        workflow:tasks:read
      )
    }
  }

  @spec all() :: [map()]
  def all do
    @profiles
    |> Enum.map(fn {key, profile} ->
      %{"key" => key, "label" => profile.label, "permissions" => profile.permissions}
    end)
    |> Enum.sort_by(& &1["key"])
  end

  @spec permissions(String.t()) :: {:ok, [String.t()]} | :error
  def permissions(key) do
    case Map.fetch(@profiles, key) do
      {:ok, profile} -> {:ok, profile.permissions}
      :error -> :error
    end
  end

  @spec valid?(term()) :: boolean()
  def valid?(key), do: is_binary(key) and Map.has_key?(@profiles, key)
end
