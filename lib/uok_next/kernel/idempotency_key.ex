defmodule UokNext.Kernel.IdempotencyKey do
  @moduledoc """
  Derives bounded internal command keys from one caller-owned idempotency key.
  """

  @spec derive(String.t(), String.t()) :: String.t()
  def derive(parent, purpose) when is_binary(parent) and is_binary(purpose) do
    digest = :crypto.hash(:sha256, [parent, 0, purpose]) |> Base.url_encode64(padding: false)
    "uok:#{digest}"
  end
end
