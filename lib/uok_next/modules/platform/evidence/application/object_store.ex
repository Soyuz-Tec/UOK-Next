defmodule UokNext.Modules.Platform.Evidence.Application.ObjectStore do
  @moduledoc """
  Provider-neutral port for bounded evidence-object bytes.

  This port is infrastructure-facing. User-visible evidence mutations must be
  implemented later as authorized, audited commands backed by PostgreSQL.
  """

  alias UokNext.Modules.Platform.Evidence.Domain.EvidenceObject

  @type receipt :: %{
          required(:provider) => String.t(),
          required(:bucket) => String.t(),
          required(:key) => String.t(),
          optional(:etag) => String.t() | nil
        }

  @callback ready?() :: :ok | {:error, atom()}
  @callback put(EvidenceObject.t(), binary()) :: {:ok, receipt()} | {:error, atom()}
  @callback fetch(EvidenceObject.t()) :: {:ok, binary()} | {:error, atom()}
  @callback delete(EvidenceObject.t()) :: :ok | {:error, atom()}
end
