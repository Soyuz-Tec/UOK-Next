defmodule UokNext.Modules.Platform.Identity.PasswordHasherTest do
  use ExUnit.Case, async: true

  alias UokNext.Modules.Platform.Identity.Infrastructure.PasswordHasher

  test "stores a versioned salted verifier and rejects malformed values" do
    password = "A unique local passphrase 2026!"
    first = PasswordHasher.hash(password)
    second = PasswordHasher.hash(password)

    assert first != second
    assert String.starts_with?(first, "pbkdf2-sha256$1000$")
    refute first =~ password
    assert PasswordHasher.verify(password, first)
    refute PasswordHasher.verify("not the password", first)
    refute PasswordHasher.verify(password, "pbkdf2-sha256$999$bad$bad")
  end
end
