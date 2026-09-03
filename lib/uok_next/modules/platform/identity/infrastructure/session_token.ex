defmodule UokNext.Modules.Platform.Identity.Infrastructure.SessionToken do
  @moduledoc false

  @behaviour UokNext.Modules.Platform.Identity.Application.SessionTokenPort

  @prefix "uokls1"

  @impl true
  @spec generate(Ecto.UUID.t()) :: String.t()
  def generate(session_id) do
    secret = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    "#{@prefix}.#{session_id}.#{secret}"
  end

  @impl true
  @spec parse(term()) :: {:ok, Ecto.UUID.t()} | :error
  def parse(token) when is_binary(token) and byte_size(token) in 80..160 do
    case String.split(token, ".", parts: 3) do
      [@prefix, session_id, secret] when byte_size(secret) == 43 -> Ecto.UUID.cast(session_id)
      _invalid -> :error
    end
  end

  def parse(_token), do: :error

  @impl true
  @spec digest(String.t()) :: binary()
  def digest(token), do: :crypto.hash(:sha256, token)

  @impl true
  @spec matches?(binary(), String.t()) :: boolean()
  def matches?(stored_hash, token) do
    presented_hash = digest(token)

    if byte_size(stored_hash) == byte_size(presented_hash) do
      Plug.Crypto.secure_compare(stored_hash, presented_hash)
    else
      false
    end
  end

  @impl true
  @spec identifier_hash(String.t()) :: binary()
  def identifier_hash(username), do: :crypto.hash(:sha256, ["local-login", 0, username])
end
