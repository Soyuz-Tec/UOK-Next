defmodule UokNext.Modules.Master.Locations.MajorSeaportReferencesTest do
  use ExUnit.Case, async: true

  import UokNext.PartyOnboardingFixtures

  alias UokNext.Modules.Master.Locations.Domain.CatalogValidation
  alias UokNext.Modules.Master.Locations.Domain.MajorSeaportCatalog
  alias UokNext.Modules.Master.Locations.Public

  test "publishes a versioned, country-indexed standard seaport catalog" do
    assert MajorSeaportCatalog.version() =~ ~r/^\d{4}-\d{2}-\d{2}-[a-f0-9]{12}$/
    assert length(MajorSeaportCatalog.countries()) == 192

    assert {:ok, ports} = MajorSeaportCatalog.list("gh")
    assert Enum.any?(ports, &(&1["reference_code"] == "GHTEM" and &1["name"] == "Tema"))
    assert Enum.any?(ports, &(&1["reference_code"] == "GHTKD" and &1["name"] == "Takoradi"))
    assert Enum.uniq_by(ports, & &1["reference_code"]) == ports
  end

  test "stores canonical bytes so provenance survives cross-platform checkout" do
    catalog_path = Application.app_dir(:uok_next, "priv/reference/major_seaports.json")
    metadata_path = Application.app_dir(:uok_next, "priv/reference/major_seaports.metadata.json")
    catalog_bytes = File.read!(catalog_path)
    metadata = metadata_path |> File.read!() |> Jason.decode!()

    refute String.contains?(catalog_bytes, "\r")

    assert :sha256
           |> :crypto.hash(catalog_bytes)
           |> Base.encode16(case: :lower) == metadata["catalog_sha256"]
  end

  test "requires named read authority and rejects malformed country input" do
    authorized = context(%{permissions: ["locations:read"]})
    denied = context(%{permissions: []})

    assert {:ok, %{"items" => countries}} = Public.list_major_seaport_countries(authorized)
    assert Enum.any?(countries, &(&1["country_code"] == "GH"))

    assert {:ok, %{"country_code" => "GH", "items" => ports}} =
             Public.list_major_seaports(" gh ", authorized)

    assert ports != []

    assert {:error, forbidden} = Public.list_major_seaport_countries(denied)
    assert forbidden.code == "forbidden"

    assert {:error, invalid} = Public.list_major_seaports("GHA", authorized)
    assert invalid.code == "validation_failed"
  end

  @tag :tmp_dir
  test "bounds reference artifacts and UTF-8 text by encoded bytes", %{tmp_dir: tmp_dir} do
    bounded_path = Path.join(tmp_dir, "bounded.json")
    oversized_path = Path.join(tmp_dir, "oversized.json")
    File.write!(bounded_path, "1234")
    File.write!(oversized_path, "12345")

    assert CatalogValidation.read_bounded!(bounded_path, 4, "test catalog") == "1234"

    assert_raise RuntimeError, "test catalog exceeds its byte limit", fn ->
      CatalogValidation.read_bounded!(oversized_path, 4, "test catalog")
    end

    two_graphemes = "Aa" <> String.duplicate("́", 100)
    assert String.length(two_graphemes) == 2
    refute CatalogValidation.bounded_text?(two_graphemes, 2..200, 200)
    assert CatalogValidation.bounded_text?("Tema", 2..200, 400)
  end
end
