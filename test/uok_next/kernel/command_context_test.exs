defmodule UokNext.Kernel.CommandContextTest do
  use ExUnit.Case, async: true

  alias UokNext.Kernel.CommandContext

  test "accepts a bounded authenticated context" do
    attrs = %{
      tenant_id: Ecto.UUID.generate(),
      actor_id: Ecto.UUID.generate(),
      correlation_id: Ecto.UUID.generate(),
      permissions: ["parties:create"]
    }

    assert {:ok, context} = CommandContext.new(attrs)
    assert CommandContext.permitted?(context, "parties:create")
    refute CommandContext.permitted?(context, "parties:approve")
  end

  test "rejects malformed identity and permission input" do
    assert {:error, error} =
             CommandContext.new(%{
               tenant_id: "not-a-uuid",
               actor_id: Ecto.UUID.generate(),
               correlation_id: Ecto.UUID.generate(),
               permissions: ["parties:create"]
             })

    assert error.code == "invalid_context"

    assert {:error, error} =
             CommandContext.new(%{
               tenant_id: Ecto.UUID.generate(),
               actor_id: Ecto.UUID.generate(),
               correlation_id: Ecto.UUID.generate(),
               permissions: ["INVALID PERMISSION"]
             })

    assert error.code == "invalid_context"
  end
end
