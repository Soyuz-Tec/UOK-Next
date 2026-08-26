defmodule UokNext.Modules.Master.Locations.Domain.MajorSeaportCatalog do
  @moduledoc "Versioned public seaport references owned by `master.locations`."

  alias UokNext.Modules.Master.Locations.Domain.CatalogValidation

  @maximum_catalog_bytes 2_000_000
  @maximum_metadata_bytes 32_000

  @catalog_path Application.app_dir(:uok_next, "priv/reference/major_seaports.json")
  @metadata_path Application.app_dir(:uok_next, "priv/reference/major_seaports.metadata.json")
  @external_resource @catalog_path
  @external_resource @metadata_path

  @catalog_bytes CatalogValidation.read_bounded!(
                   @catalog_path,
                   @maximum_catalog_bytes,
                   "major seaport catalog"
                 )
  @metadata_bytes CatalogValidation.read_bounded!(
                    @metadata_path,
                    @maximum_metadata_bytes,
                    "major seaport metadata"
                  )
  @metadata Jason.decode!(@metadata_bytes)
  @catalog_sha256 :crypto.hash(:sha256, @catalog_bytes) |> Base.encode16(case: :lower)

  unless @metadata["schema_version"] == 1 do
    raise "major seaport catalog uses an unsupported provenance schema"
  end

  unless @catalog_sha256 == @metadata["catalog_sha256"] do
    raise "major seaport catalog digest does not match its provenance metadata"
  end

  @ports Jason.decode!(@catalog_bytes)

  unless is_list(@ports) and length(@ports) in 3_000..4_000 and
           Enum.all?(@ports, fn port ->
             is_map(port) and
               Map.keys(port) |> Enum.sort() ==
                 ~w(catalog_number country_code country_name harbor_scale name reference_code) and
               Regex.match?(~r/^[A-Z]{2}[A-Z0-9]{3}$/, port["reference_code"]) and
               String.starts_with?(port["reference_code"], port["country_code"]) and
               Regex.match?(~r/^[A-Z]{2}$/, port["country_code"]) and
               CatalogValidation.bounded_text?(port["country_name"], 2..100, 200) and
               CatalogValidation.bounded_text?(port["name"], 2..200, 400) and
               port["harbor_scale"] in ~w(large medium small very_small unclassified) and
               Regex.match?(~r/^\d{1,12}$/, port["catalog_number"])
           end) do
    raise "major seaport catalog contains an invalid record"
  end

  unless @ports |> Enum.map(& &1["reference_code"]) |> Enum.uniq() |> length() == length(@ports) do
    raise "major seaport catalog contains duplicate standardized codes"
  end

  unless length(@ports) == @metadata["record_count"] do
    raise "major seaport catalog count does not match its provenance metadata"
  end

  @ports_by_country Enum.group_by(@ports, & &1["country_code"])

  @countries @ports_by_country
             |> Enum.map(fn {country_code, ports} ->
               %{
                 "country_code" => country_code,
                 "country_name" => ports |> List.first() |> Map.fetch!("country_name"),
                 "port_count" => length(ports)
               }
             end)
             |> Enum.sort_by(&{&1["country_name"], &1["country_code"]})

  unless length(@countries) == @metadata["country_count"] do
    raise "major seaport country count does not match its provenance metadata"
  end

  @spec version() :: String.t()
  def version, do: @metadata["catalog_version"]

  @spec countries() :: [map()]
  def countries, do: @countries

  @spec list(String.t()) :: {:ok, [map()]} | {:error, map()}
  def list(country_code) when is_binary(country_code) do
    normalized = country_code |> String.trim() |> String.upcase()

    if Regex.match?(~r/^[A-Z]{2}$/, normalized) do
      {:ok, Map.get(@ports_by_country, normalized, [])}
    else
      {:error, %{country_code: ["must be a two-letter code"]}}
    end
  end

  def list(_country_code), do: {:error, %{country_code: ["must be a two-letter code"]}}
end
