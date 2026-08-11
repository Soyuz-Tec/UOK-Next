defmodule UokNext.Kernel.ReleaseIdentityTest do
  use ExUnit.Case, async: false

  alias UokNext.Kernel.ReleaseIdentity

  test "reports stable service and application identity" do
    identity = ReleaseIdentity.current()

    assert identity.service == "uok-next"
    assert identity.version == "0.1.0"
    assert identity.revision == Application.fetch_env!(:uok_next, :build_revision)
  end

  test "runtime environment cannot override the compiled release revision" do
    previous = System.get_env("UOK_REVISION")
    on_exit(fn -> restore_environment("UOK_REVISION", previous) end)

    System.put_env("UOK_REVISION", String.duplicate("0", 40))

    assert ReleaseIdentity.current().revision ==
             Application.fetch_env!(:uok_next, :build_revision)
  end

  defp restore_environment(name, nil), do: System.delete_env(name)
  defp restore_environment(name, value), do: System.put_env(name, value)
end
