defmodule UokNext.Modules.Master.Locations.Public do
  @moduledoc "Supported command and query boundary for `master.locations`."

  alias UokNext.Modules.Master.Locations.Application.Locations
  alias UokNext.Modules.Master.Locations.Application.MajorSeaportReferences
  alias UokNext.Modules.Master.Locations.Infrastructure.EctoLocationStore

  @spec create(map(), UokNext.Kernel.CommandContext.t(), String.t()) :: tuple()
  def create(attrs, context, idempotency_key),
    do: Locations.create(EctoLocationStore, attrs, context, idempotency_key)

  @spec get(String.t(), UokNext.Kernel.CommandContext.t()) :: tuple()
  def get(location_id, context), do: Locations.get(EctoLocationStore, location_id, context)

  @spec require_active(String.t(), UokNext.Kernel.CommandContext.t()) :: tuple()
  def require_active(location_id, context),
    do: Locations.require_active(EctoLocationStore, location_id, context)

  @spec list(pos_integer(), UokNext.Kernel.CommandContext.t()) :: tuple()
  def list(limit, context), do: Locations.list(EctoLocationStore, limit, context)

  @spec list_major_seaport_countries(UokNext.Kernel.CommandContext.t()) :: tuple()
  def list_major_seaport_countries(context), do: MajorSeaportReferences.countries(context)

  @spec list_major_seaports(String.t(), UokNext.Kernel.CommandContext.t()) :: tuple()
  def list_major_seaports(country_code, context),
    do: MajorSeaportReferences.list(country_code, context)
end
