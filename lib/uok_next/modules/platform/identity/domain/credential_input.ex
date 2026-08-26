defmodule UokNext.Modules.Platform.Identity.Domain.CredentialInput do
  @moduledoc false

  @common_passwords MapSet.new(~w(
    123456789012345
    administrator
    changemechangeme
    correcthorsebatterystaple
    letmeinletmein
    passwordpassword
    password123456
    qwertyqwertyqwerty
    welcome123456789
  ))

  @spec validate_password(term()) :: {:ok, String.t()} | {:error, map()}
  def validate_password(password) when is_binary(password) do
    cond do
      not String.valid?(password) or not String.printable?(password) ->
        error("password", "must contain only printable characters")

      String.length(password) not in 15..128 ->
        error("password", "must contain 15 to 128 characters")

      common?(password) ->
        error("password", "is too common; choose a longer unique passphrase")

      true ->
        {:ok, password}
    end
  end

  def validate_password(_password), do: error("password", "must contain 15 to 128 characters")

  @spec validate_confirmation(String.t(), term()) :: :ok | {:error, map()}
  def validate_confirmation(password, password), do: :ok

  def validate_confirmation(_password, _confirmation),
    do: error("password_confirmation", "does not match")

  @spec validate_current_password(term()) :: {:ok, String.t()} | {:error, map()}
  def validate_current_password(password)
      when is_binary(password) and byte_size(password) in 1..512,
      do: {:ok, password}

  def validate_current_password(_password), do: error("current_password", "is invalid")

  defp common?(password) do
    normalized =
      password
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]/u, "")

    MapSet.member?(@common_passwords, normalized)
  end

  defp error(field, message), do: {:error, %{field: field, message: message}}
end
