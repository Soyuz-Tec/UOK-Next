defmodule UokNext.Modules.Platform.Identity.Application.SessionTokenPort do
  @moduledoc false

  @callback generate(Ecto.UUID.t()) :: String.t()
  @callback parse(term()) :: {:ok, Ecto.UUID.t()} | :error
  @callback digest(String.t()) :: binary()
  @callback matches?(binary(), String.t()) :: boolean()
  @callback identifier_hash(String.t()) :: binary()
end
