defmodule UokNext.Repo.Migrations.CreateProductLocationSourcingAuthority do
  use Ecto.Migration

  def up do
    create unique_index(:master_parties, [:tenant_id, :id],
             name: :master_parties_tenant_identity_index
           )

    create_products()
    create_locations()
    create_sourcing_lanes()
    add_sourcing_references()
    enable_tenant_isolation()
  end

  def down do
    execute "DROP POLICY IF EXISTS trade_sourcing_lanes_tenant_isolation ON trade_sourcing_lanes"
    execute "DROP POLICY IF EXISTS master_locations_tenant_isolation ON master_locations"
    execute "DROP POLICY IF EXISTS master_products_tenant_isolation ON master_products"
    drop table(:trade_sourcing_lanes)
    drop table(:master_locations)
    drop table(:master_products)

    drop index(:master_parties, [:tenant_id, :id], name: :master_parties_tenant_identity_index)
  end

  defp create_products do
    create table(:master_products, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :stable_identifier, :string, null: false, size: 100
      add :name, :string, null: false, size: 200
      add :product_kind, :string, null: false, size: 32
      add :base_unit_code, :string, null: false, size: 16
      add :status, :string, null: false, size: 16, default: "active"
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:master_products, [:tenant_id, :id],
             name: :master_products_tenant_identity_index
           )

    create unique_index(:master_products, [:tenant_id, :stable_identifier],
             name: :master_products_tenant_stable_identifier_index
           )

    create index(:master_products, [:tenant_id, :status],
             name: :master_products_tenant_status_index
           )

    create constraint(:master_products, :master_products_identifier_check,
             check: "stable_identifier ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{1,99}$'"
           )

    create constraint(:master_products, :master_products_kind_check,
             check: "product_kind IN ('commodity', 'packaging', 'service')"
           )

    create constraint(:master_products, :master_products_unit_code_check,
             check: "base_unit_code ~ '^[A-Z][A-Z0-9._-]{0,15}$'"
           )

    create constraint(:master_products, :master_products_status_check, check: "status = 'active'")

    create constraint(:master_products, :master_products_version_check, check: "lock_version > 0")
  end

  defp create_locations do
    create table(:master_locations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :stable_identifier, :string, null: false, size: 100
      add :name, :string, null: false, size: 200
      add :country_code, :string, null: false, size: 2
      add :location_kind, :string, null: false, size: 32
      add :status, :string, null: false, size: 16, default: "active"
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:master_locations, [:tenant_id, :id],
             name: :master_locations_tenant_identity_index
           )

    create unique_index(:master_locations, [:tenant_id, :stable_identifier],
             name: :master_locations_tenant_stable_identifier_index
           )

    create index(:master_locations, [:tenant_id, :status],
             name: :master_locations_tenant_status_index
           )

    create constraint(:master_locations, :master_locations_identifier_check,
             check: "stable_identifier ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{1,99}$'"
           )

    create constraint(:master_locations, :master_locations_country_code_check,
             check: "country_code ~ '^[A-Z]{2}$'"
           )

    create constraint(:master_locations, :master_locations_kind_check,
             check: "location_kind IN ('country', 'region', 'locality', 'port', 'facility')"
           )

    create constraint(:master_locations, :master_locations_status_check,
             check: "status = 'active'"
           )

    create constraint(:master_locations, :master_locations_version_check,
             check: "lock_version > 0"
           )
  end

  defp create_sourcing_lanes do
    create table(:trade_sourcing_lanes, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :stable_identifier, :string, null: false, size: 100
      add :name, :string, null: false, size: 200
      add :supplier_party_id, :uuid, null: false
      add :product_id, :uuid, null: false
      add :origin_location_id, :uuid, null: false
      add :destination_location_id, :uuid, null: false
      add :status, :string, null: false, size: 32, default: "draft"
      add :evidence_metadata, :map
      add :evidence_submitted_at, :utc_datetime_usec
      add :decision_reason, :string, size: 500
      add :decision_actor_id, :uuid
      add :decided_at, :utc_datetime_usec
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:trade_sourcing_lanes, [:tenant_id, :id],
             name: :trade_sourcing_lanes_tenant_identity_index
           )

    create unique_index(:trade_sourcing_lanes, [:tenant_id, :stable_identifier],
             name: :trade_sourcing_lanes_tenant_stable_identifier_index
           )

    create index(:trade_sourcing_lanes, [:tenant_id, :status],
             name: :trade_sourcing_lanes_tenant_status_index
           )

    create constraint(:trade_sourcing_lanes, :trade_sourcing_lanes_identifier_check,
             check: "stable_identifier ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{1,99}$'"
           )

    create constraint(:trade_sourcing_lanes, :trade_sourcing_lanes_status_check,
             check: "status IN ('draft', 'evidence_submitted', 'approved', 'hold')"
           )

    create constraint(:trade_sourcing_lanes, :trade_sourcing_lanes_route_check,
             check: "origin_location_id <> destination_location_id"
           )

    create constraint(:trade_sourcing_lanes, :trade_sourcing_lanes_version_check,
             check: "lock_version > 0"
           )

    create constraint(:trade_sourcing_lanes, :trade_sourcing_lanes_lifecycle_check,
             check: """
             (status = 'draft' AND evidence_metadata IS NULL AND evidence_submitted_at IS NULL AND
              decision_reason IS NULL AND decision_actor_id IS NULL AND decided_at IS NULL) OR
             (status = 'evidence_submitted' AND evidence_metadata IS NOT NULL AND
              evidence_submitted_at IS NOT NULL AND decision_reason IS NULL AND
              decision_actor_id IS NULL AND decided_at IS NULL) OR
             (status IN ('approved', 'hold') AND evidence_metadata IS NOT NULL AND
              evidence_submitted_at IS NOT NULL AND decision_reason IS NOT NULL AND
              decision_actor_id IS NOT NULL AND decided_at IS NOT NULL)
             """
           )
  end

  defp add_sourcing_references do
    execute """
    ALTER TABLE trade_sourcing_lanes
    ADD CONSTRAINT trade_sourcing_lanes_tenant_supplier_fkey
    FOREIGN KEY (tenant_id, supplier_party_id)
    REFERENCES master_parties (tenant_id, id)
    ON DELETE RESTRICT
    """

    execute """
    ALTER TABLE trade_sourcing_lanes
    ADD CONSTRAINT trade_sourcing_lanes_tenant_product_fkey
    FOREIGN KEY (tenant_id, product_id)
    REFERENCES master_products (tenant_id, id)
    ON DELETE RESTRICT
    """

    execute """
    ALTER TABLE trade_sourcing_lanes
    ADD CONSTRAINT trade_sourcing_lanes_tenant_origin_fkey
    FOREIGN KEY (tenant_id, origin_location_id)
    REFERENCES master_locations (tenant_id, id)
    ON DELETE RESTRICT
    """

    execute """
    ALTER TABLE trade_sourcing_lanes
    ADD CONSTRAINT trade_sourcing_lanes_tenant_destination_fkey
    FOREIGN KEY (tenant_id, destination_location_id)
    REFERENCES master_locations (tenant_id, id)
    ON DELETE RESTRICT
    """
  end

  defp enable_tenant_isolation do
    for table <- ~w(master_products master_locations trade_sourcing_lanes) do
      execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY"
      execute "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY"

      execute """
      CREATE POLICY #{table}_tenant_isolation
      ON #{table}
      USING (tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid)
      WITH CHECK (tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid)
      """
    end
  end
end
