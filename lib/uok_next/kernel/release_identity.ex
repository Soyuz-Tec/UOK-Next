defmodule UokNext.Kernel.ReleaseIdentity do
  @moduledoc """
  Reports immutable application identity without exposing host secrets.

  Deployments provide `UOK_REVISION` from the exact source revision used to
  build the release. Local development deliberately reports `uncommitted` when
  no revision is supplied.
  """

  @spec current() :: %{service: String.t(), version: String.t(), revision: String.t()}
  def current do
    %{
      service: "uok-next",
      version: application_version(),
      revision: System.get_env("UOK_REVISION", "uncommitted")
    }
  end

  defp application_version do
    :uok_next
    |> Application.spec(:vsn)
    |> to_string()
  end
end
