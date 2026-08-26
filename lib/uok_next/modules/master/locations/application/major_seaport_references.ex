defmodule UokNext.Modules.Master.Locations.Application.MajorSeaportReferences do
  @moduledoc false

  alias UokNext.Kernel.{CommandContext, CommandError}
  alias UokNext.Modules.Master.Locations.Domain.MajorSeaportCatalog
  alias UokNext.Modules.Master.Locations.Policies.Authorization

  @read_permission "locations:read"

  @spec countries(CommandContext.t()) :: {:ok, map()} | {:error, CommandError.t()}
  def countries(context) do
    with :ok <- Authorization.require_permission(context, @read_permission) do
      {:ok,
       %{
         "catalog_version" => MajorSeaportCatalog.version(),
         "items" => MajorSeaportCatalog.countries()
       }}
    end
  end

  @spec list(String.t(), CommandContext.t()) :: {:ok, map()} | {:error, CommandError.t()}
  def list(country_code, context) do
    with :ok <- Authorization.require_permission(context, @read_permission),
         {:ok, ports} <- MajorSeaportCatalog.list(country_code) do
      {:ok,
       %{
         "catalog_version" => MajorSeaportCatalog.version(),
         "country_code" => String.upcase(String.trim(country_code)),
         "items" => ports
       }}
    else
      {:error, %CommandError{} = error} -> {:error, error}
      {:error, details} -> validation_error(details)
    end
  end

  defp validation_error(details) do
    {:error,
     CommandError.new(
       "validation_failed",
       "major seaport reference validation failed",
       422,
       details
     )}
  end
end
