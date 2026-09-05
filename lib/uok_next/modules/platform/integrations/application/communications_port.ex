defmodule UokNext.Modules.Platform.Integrations.Application.CommunicationsPort do
  @moduledoc """
  Application-owned port for independent communications authorization and local handoff.

  Implementations reauthorize every operation using their own current access authority.
  Proofs and receipts echo the complete envelope digest and contain no communication content.
  """

  @callback health() :: {:ok, map()} | {:error, atom()}
  @callback authorize(map()) :: {:ok, map()} | {:error, atom()}
  @callback deliver(map()) :: {:ok, map()} | {:error, atom()}
  @callback reconcile(map()) :: {:ok, map()} | {:error, atom()}
end
