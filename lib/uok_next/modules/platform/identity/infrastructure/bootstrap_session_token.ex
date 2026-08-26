defmodule UokNext.Modules.Platform.Identity.Infrastructure.BootstrapSessionToken do
  @moduledoc false

  @behaviour UokNext.Modules.Platform.Identity.Application.BootstrapSessionTokenPort

  @prefix "uokba1"

  @impl true
  def generate(session_id) do
    secret = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    "#{@prefix}.#{session_id}.#{secret}"
  end

  @impl true
  def parse(token) when is_binary(token) and byte_size(token) in 80..160 do
    case String.split(token, ".", parts: 3) do
      [@prefix, session_id, secret] when byte_size(secret) == 43 -> Ecto.UUID.cast(session_id)
      _invalid -> :error
    end
  end

  def parse(_token), do: :error

  @impl true
  def digest(token), do: :crypto.hash(:sha256, token)

  @impl true
  def matches?(stored_hash, token) when is_binary(stored_hash) and is_binary(token) do
    presented_hash = digest(token)

    if byte_size(stored_hash) == byte_size(presented_hash) do
      Plug.Crypto.secure_compare(stored_hash, presented_hash)
    else
      false
    end
  end

  def matches?(_stored_hash, _token), do: false
end
