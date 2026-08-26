defmodule UokNext.Modules.Platform.Identity.Application.BootstrapIdentityPort do
  @moduledoc false

  @callback authenticate(term()) :: {:ok, map()} | :error
  @callback current() :: {:ok, map()} | :error
end
