defmodule UokNext.Modules.Platform.Identity.Domain.LocalUser do
  @moduledoc false

  alias UokNext.Modules.Platform.Identity.Domain.{AccessProfile, CredentialInput}

  @username_pattern ~r/^[a-z0-9][a-z0-9._-]{2,63}$/

  @spec validate_create(map()) :: {:ok, map()} | {:error, map()}
  def validate_create(attrs) when is_map(attrs) do
    with {:ok, username} <- username(value(attrs, "username")),
         {:ok, display_name} <- display_name(value(attrs, "display_name")),
         {:ok, access_profile} <- access_profile(value(attrs, "access_profile")),
         {:ok, temporary_password} <-
           CredentialInput.validate_password(value(attrs, "temporary_password")),
         {:ok, reason} <- reason(value(attrs, "reason")) do
      {:ok,
       %{
         username: username,
         normalized_username: String.downcase(username),
         display_name: display_name,
         access_profile: access_profile,
         temporary_password: temporary_password,
         reason: reason
       }}
    end
  end

  def validate_create(_attrs), do: error("command", "must be an object")

  @spec normalize_login(term()) :: {:ok, String.t()} | :error
  def normalize_login(username) when is_binary(username) do
    if String.valid?(username) do
      normalized = username |> String.trim() |> String.downcase()
      if Regex.match?(@username_pattern, normalized), do: {:ok, normalized}, else: :error
    else
      :error
    end
  end

  def normalize_login(_username), do: :error

  defp username(value) when is_binary(value) do
    with true <- String.valid?(value),
         normalized <- value |> String.trim() |> String.downcase(),
         true <- Regex.match?(@username_pattern, normalized) do
      {:ok, normalized}
    else
      _invalid ->
        error(
          "username",
          "must contain 3 to 64 lowercase letters, numbers, dots, dashes, or underscores"
        )
    end
  end

  defp username(_value), do: error("username", "must contain 3 to 64 safe characters")

  defp display_name(value), do: bounded_text(value, "display_name", 2, 120)
  defp reason(value), do: bounded_text(value, "reason", 3, 500)

  defp access_profile(value) do
    if AccessProfile.valid?(value),
      do: {:ok, value},
      else: error("access_profile", "is not allowed")
  end

  defp bounded_text(value, field, minimum, maximum) when is_binary(value) do
    normalized = String.trim(value)

    if String.printable?(normalized) and String.length(normalized) in minimum..maximum do
      {:ok, normalized}
    else
      error(field, "must contain #{minimum} to #{maximum} printable characters")
    end
  end

  defp bounded_text(_value, field, minimum, maximum),
    do: error(field, "must contain #{minimum} to #{maximum} printable characters")

  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, key_atom(key))
  defp key_atom("username"), do: :username
  defp key_atom("display_name"), do: :display_name
  defp key_atom("access_profile"), do: :access_profile
  defp key_atom("temporary_password"), do: :temporary_password
  defp key_atom("reason"), do: :reason
  defp error(field, message), do: {:error, %{field: field, message: message}}
end
