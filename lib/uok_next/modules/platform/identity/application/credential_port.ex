defmodule UokNext.Modules.Platform.Identity.Application.CredentialPort do
  @moduledoc false

  @callback hash(String.t()) :: String.t()
  @callback verify(String.t(), String.t()) :: boolean()
  @callback no_user_verify() :: false
  @callback fingerprint(String.t(), String.t()) :: String.t()
end
