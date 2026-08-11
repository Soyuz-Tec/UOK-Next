defmodule UokNext.Kernel.ReleaseIdentity do
  @moduledoc """
  Reports immutable application identity without exposing host secrets.

  The container build compiles `UOK_BUILD_REVISION` into the release. Runtime
  environment changes therefore cannot make a different image claim the
  expected source revision. Local development reports `uncommitted`.
  """

  @spec current() :: %{service: String.t(), version: String.t(), revision: String.t()}
  def current do
    %{
      service: "uok-next",
      version: application_version(),
      revision: Application.fetch_env!(:uok_next, :build_revision)
    }
  end

  defp application_version do
    :uok_next
    |> Application.spec(:vsn)
    |> to_string()
  end
end
