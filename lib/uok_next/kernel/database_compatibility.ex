defmodule UokNext.Kernel.DatabaseCompatibility do
  @moduledoc false

  @query "SELECT current_setting('server_version_num')::integer, current_setting('server_version')"

  @spec verify(module()) :: :ok | {:error, String.t()}
  def verify(repo) do
    target_major = Application.fetch_env!(:uok_next, :database_target_major)
    prerelease_allowed? = Application.fetch_env!(:uok_next, :database_prerelease_allowed)

    case repo.query(@query, [], timeout: 2_000) do
      {:ok, %{rows: [[version_number, version_name]]}} ->
        verify_version(version_number, version_name, target_major, prerelease_allowed?)

      {:error, _error} ->
        {:error, "database_version_unavailable"}

      _unexpected ->
        {:error, "database_version_invalid"}
    end
  end

  @spec verify!(module()) :: :ok
  def verify!(repo) do
    case verify(repo) do
      :ok -> :ok
      {:error, reason} -> raise "database compatibility preflight failed: #{reason}"
    end
  end

  defp verify_version(version_number, version_name, target_major, prerelease_allowed?)
       when is_integer(version_number) and is_binary(version_name) do
    cond do
      div(version_number, 10_000) != target_major ->
        {:error, "database_version_unsupported"}

      not prerelease_allowed? and prerelease?(version_name) ->
        {:error, "database_prerelease_forbidden"}

      true ->
        :ok
    end
  end

  defp verify_version(_version_number, _version_name, _target_major, _prerelease_allowed?),
    do: {:error, "database_version_invalid"}

  defp prerelease?(version_name), do: Regex.match?(~r/(alpha|beta|rc|devel)/i, version_name)
end
