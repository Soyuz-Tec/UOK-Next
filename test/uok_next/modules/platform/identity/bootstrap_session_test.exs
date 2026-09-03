defmodule UokNext.Modules.Platform.Identity.BootstrapSessionTest do
  use UokNext.DataCase, async: false

  alias UokNext.Kernel.CommandContext
  alias UokNext.Modules.Platform.Identity.Public

  @access_code "uok-next-test-access-code-00000001"

  test "issues and verifies only the configured local tenant identity" do
    assert {:ok, session} = Public.authenticate_local(@access_code)
    assert session["token_type"] == "Bearer"

    assert {:ok, identity} = Public.verify_access_token(session["access_token"])
    assert identity == session["identity"]
    assert "parties:create" in identity["permissions"]

    assert {:ok, context} =
             CommandContext.new(%{
               tenant_id: identity["tenant_id"],
               actor_id: identity["actor_id"],
               correlation_id: Ecto.UUID.generate(),
               permissions: identity["permissions"]
             })

    assert {:ok, %{"revoked" => true}, :executed} =
             Public.revoke_access_token(session["access_token"], context)

    assert {:error, revoked} = Public.verify_access_token(session["access_token"])
    assert revoked.code == "unauthorized"
  end

  test "rejects invalid codes, forged tokens, and production profile activation" do
    assert {:error, invalid} = Public.authenticate_local(String.duplicate("x", 32))
    assert invalid.code == "unauthorized"
    assert {:error, forged} = Public.verify_access_token(String.duplicate("x", 64))
    assert forged.code == "unauthorized"

    previous = Application.get_env(:uok_next, :deployment_profile)
    Application.put_env(:uok_next, :deployment_profile, :production)

    on_exit(fn -> Application.put_env(:uok_next, :deployment_profile, previous) end)

    assert {:error, disabled} = Public.authenticate_local(@access_code)
    assert disabled.code == "unauthorized"
  end
end
