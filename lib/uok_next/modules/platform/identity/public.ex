defmodule UokNext.Modules.Platform.Identity.Public do
  @moduledoc """
  Supported identity boundary for the isolated local qualification profile.

  A production identity adapter is intentionally not selected by this module.
  """

  alias UokNext.Modules.Platform.Identity.Infrastructure.SignedAccessToken

  @spec authenticate_local(String.t()) :: tuple()
  def authenticate_local(access_code), do: SignedAccessToken.authenticate_local(access_code)

  @spec verify_access_token(String.t()) :: tuple()
  def verify_access_token(token), do: SignedAccessToken.verify(token)
end
