defmodule UokNext.Modules.Platform.Identity.Infrastructure.PasswordHasher do
  @moduledoc false

  @behaviour UokNext.Modules.Platform.Identity.Application.CredentialPort

  @algorithm "pbkdf2-sha256"
  @salt_bytes 16
  @hash_bytes 32

  @impl true
  @spec hash(String.t()) :: String.t()
  def hash(password) do
    iterations = iterations()
    salt = :crypto.strong_rand_bytes(@salt_bytes)
    derived = derive(password, salt, iterations)

    Enum.join(
      [
        @algorithm,
        Integer.to_string(iterations),
        Base.url_encode64(salt, padding: false),
        Base.url_encode64(derived, padding: false)
      ],
      "$"
    )
  end

  @impl true
  @spec verify(String.t(), String.t()) :: boolean()
  def verify(password, encoded) when is_binary(password) and is_binary(encoded) do
    with [@algorithm, encoded_iterations, encoded_salt, encoded_hash] <-
           String.split(encoded, "$", parts: 4),
         {iterations, ""} when iterations in 1_000..2_000_000 <-
           Integer.parse(encoded_iterations),
         {:ok, salt} when byte_size(salt) == @salt_bytes <-
           Base.url_decode64(encoded_salt, padding: false),
         {:ok, expected} when byte_size(expected) == @hash_bytes <-
           Base.url_decode64(encoded_hash, padding: false) do
      Plug.Crypto.secure_compare(derive(password, salt, iterations), expected)
    else
      _invalid -> false
    end
  end

  def verify(_password, _encoded), do: false

  @impl true
  @spec no_user_verify() :: false
  def no_user_verify do
    derive("not-a-valid-user", <<0::128>>, iterations())
    false
  end

  @impl true
  @spec fingerprint(String.t(), String.t()) :: String.t()
  def fingerprint(purpose, value) do
    endpoint_config = Application.fetch_env!(:uok_next, UokNextWeb.Endpoint)
    secret = Keyword.fetch!(endpoint_config, :secret_key_base)

    :crypto.mac(:hmac, :sha256, secret, [purpose, 0, value])
    |> Base.url_encode64(padding: false)
  end

  defp iterations, do: Application.fetch_env!(:uok_next, :password_hash_iterations)

  defp derive(password, salt, iterations) do
    :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, @hash_bytes)
  end
end
