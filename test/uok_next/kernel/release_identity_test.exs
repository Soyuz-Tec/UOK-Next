defmodule UokNext.Kernel.ReleaseIdentityTest do
  use ExUnit.Case, async: true

  alias UokNext.Kernel.ReleaseIdentity

  test "reports stable service and application identity" do
    identity = ReleaseIdentity.current()

    assert identity.service == "uok-next"
    assert identity.version == "0.1.0"
    assert is_binary(identity.revision)
    assert identity.revision != ""
  end
end
