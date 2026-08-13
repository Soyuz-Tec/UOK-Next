defmodule UokNext.Repo.Migrations.CreateRfqQuoteComparisonVertical do
  @moduledoc "Owned by trade.sourcing; forward migration for ADR-0019."

  use Ecto.Migration

  @tables ~w(
    trade_purchase_requisitions
    trade_rfqs
    trade_rfq_suppliers
    trade_supplier_quotes
    trade_quote_comparisons
  )

  def up do
    create_requisitions()
    create_rfqs()
    create_rfq_suppliers()
    create_supplier_quotes()
    create_quote_comparisons()
    add_references()
    enable_tenant_isolation()
  end

  def down do
    for table <- Enum.reverse(@tables) do
      execute "DROP POLICY IF EXISTS #{table}_tenant_isolation ON #{table}"
      drop table(String.to_existing_atom(table))
    end
  end

  defp create_requisitions do
    create table(:trade_purchase_requisitions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :stable_identifier, :string, null: false, size: 100
      add :sourcing_lane_id, :uuid, null: false
      add :sourcing_lane_version, :integer, null: false
      add :quantity, :decimal, null: false, precision: 20, scale: 6
      add :unit_code, :string, null: false, size: 16
      add :required_by, :date, null: false
      add :status, :string, null: false, size: 24, default: "ready_for_rfq"
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    identity_indexes(:trade_purchase_requisitions)
    create unique_index(:trade_purchase_requisitions, [:tenant_id, :stable_identifier])
    positive_version(:trade_purchase_requisitions)

    create constraint(
             :trade_purchase_requisitions,
             :trade_purchase_requisitions_source_version_check,
             check: "sourcing_lane_version > 0"
           )

    create constraint(:trade_purchase_requisitions, :trade_purchase_requisitions_quantity_check,
             check: "quantity > 0"
           )

    create constraint(:trade_purchase_requisitions, :trade_purchase_requisitions_unit_check,
             check: "unit_code ~ '^[A-Z][A-Z0-9._-]{0,15}$'"
           )

    create constraint(:trade_purchase_requisitions, :trade_purchase_requisitions_status_check,
             check: "status IN ('ready_for_rfq', 'rfq_open')"
           )
  end

  defp create_rfqs do
    create table(:trade_rfqs, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :stable_identifier, :string, null: false, size: 100
      add :requisition_id, :uuid, null: false
      add :requisition_version, :integer, null: false
      add :settlement_currency_code, :string, null: false, size: 3
      add :response_deadline, :utc_datetime_usec, null: false
      add :status, :string, null: false, size: 24, default: "open"
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    identity_indexes(:trade_rfqs)
    create unique_index(:trade_rfqs, [:tenant_id, :stable_identifier])
    create unique_index(:trade_rfqs, [:tenant_id, :requisition_id])
    positive_version(:trade_rfqs)

    create constraint(:trade_rfqs, :trade_rfqs_source_version_check,
             check: "requisition_version > 0"
           )

    create constraint(:trade_rfqs, :trade_rfqs_currency_check,
             check: "settlement_currency_code ~ '^[A-Z]{3}$'"
           )

    create constraint(:trade_rfqs, :trade_rfqs_status_check,
             check: "status IN ('open', 'comparison_pending', 'compared', 'hold')"
           )
  end

  defp create_rfq_suppliers do
    create table(:trade_rfq_suppliers, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :rfq_id, :uuid, null: false
      add :supplier_party_id, :uuid, null: false
      add :supplier_party_version, :integer, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:trade_rfq_suppliers, [:tenant_id, :id])
    create unique_index(:trade_rfq_suppliers, [:tenant_id, :rfq_id, :supplier_party_id])
    create index(:trade_rfq_suppliers, [:tenant_id, :supplier_party_id])

    create constraint(:trade_rfq_suppliers, :trade_rfq_suppliers_party_version_check,
             check: "supplier_party_version > 0"
           )
  end

  defp create_supplier_quotes do
    create table(:trade_supplier_quotes, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :stable_identifier, :string, null: false, size: 100
      add :rfq_id, :uuid, null: false
      add :supplier_party_id, :uuid, null: false
      add :quoted_quantity, :decimal, null: false, precision: 20, scale: 6
      add :unit_price, :decimal, null: false, precision: 20, scale: 6
      add :currency_code, :string, null: false, size: 3
      add :delivery_days, :integer, null: false
      add :status, :string, null: false, size: 24, default: "draft"
      add :evidence_metadata, :map
      add :submitted_at, :utc_datetime_usec
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    identity_indexes(:trade_supplier_quotes)
    create unique_index(:trade_supplier_quotes, [:tenant_id, :stable_identifier])
    create unique_index(:trade_supplier_quotes, [:tenant_id, :rfq_id, :supplier_party_id])

    create unique_index(:trade_supplier_quotes, [:tenant_id, :rfq_id, :id],
             name: :trade_supplier_quotes_tenant_rfq_identity_index
           )

    positive_version(:trade_supplier_quotes)

    create constraint(:trade_supplier_quotes, :trade_supplier_quotes_values_check,
             check: "quoted_quantity > 0 AND unit_price > 0 AND delivery_days BETWEEN 0 AND 3650"
           )

    create constraint(:trade_supplier_quotes, :trade_supplier_quotes_currency_check,
             check: "currency_code ~ '^[A-Z]{3}$'"
           )

    create constraint(:trade_supplier_quotes, :trade_supplier_quotes_status_check,
             check: "status IN ('draft', 'submitted')"
           )

    create constraint(:trade_supplier_quotes, :trade_supplier_quotes_lifecycle_check,
             check:
               "(status = 'draft' AND evidence_metadata IS NULL AND submitted_at IS NULL) OR " <>
                 "(status = 'submitted' AND evidence_metadata IS NOT NULL AND submitted_at IS NOT NULL)"
           )
  end

  defp create_quote_comparisons do
    create table(:trade_quote_comparisons, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :stable_identifier, :string, null: false, size: 100
      add :rfq_id, :uuid, null: false
      add :rfq_version, :integer, null: false
      add :recommended_quote_id, :uuid, null: false
      add :ranking_snapshot, :map, null: false
      add :status, :string, null: false, size: 24, default: "awaiting_review"
      add :decision_reason, :string, size: 500
      add :decision_actor_id, :uuid
      add :decided_at, :utc_datetime_usec
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    identity_indexes(:trade_quote_comparisons)
    create unique_index(:trade_quote_comparisons, [:tenant_id, :stable_identifier])
    create unique_index(:trade_quote_comparisons, [:tenant_id, :rfq_id])
    positive_version(:trade_quote_comparisons)

    create constraint(:trade_quote_comparisons, :trade_quote_comparisons_source_version_check,
             check: "rfq_version > 0"
           )

    create constraint(:trade_quote_comparisons, :trade_quote_comparisons_status_check,
             check: "status IN ('awaiting_review', 'approved', 'hold')"
           )

    create constraint(:trade_quote_comparisons, :trade_quote_comparisons_lifecycle_check,
             check:
               "(status = 'awaiting_review' AND decision_reason IS NULL AND " <>
                 "decision_actor_id IS NULL AND decided_at IS NULL) OR " <>
                 "(status IN ('approved', 'hold') AND decision_reason IS NOT NULL AND " <>
                 "decision_actor_id IS NOT NULL AND decided_at IS NOT NULL)"
           )
  end

  defp add_references do
    tenant_fk(:trade_purchase_requisitions, :sourcing_lane_id, :trade_sourcing_lanes)
    tenant_fk(:trade_rfqs, :requisition_id, :trade_purchase_requisitions)
    tenant_fk(:trade_rfq_suppliers, :rfq_id, :trade_rfqs)
    tenant_fk(:trade_rfq_suppliers, :supplier_party_id, :master_parties)
    tenant_fk(:trade_supplier_quotes, :rfq_id, :trade_rfqs)
    tenant_fk(:trade_supplier_quotes, :supplier_party_id, :master_parties)
    tenant_fk(:trade_quote_comparisons, :rfq_id, :trade_rfqs)
    tenant_fk(:trade_quote_comparisons, :recommended_quote_id, :trade_supplier_quotes)

    execute """
    ALTER TABLE trade_quote_comparisons
    ADD CONSTRAINT trade_quote_comparisons_tenant_rfq_recommended_quote_fkey
    FOREIGN KEY (tenant_id, rfq_id, recommended_quote_id)
    REFERENCES trade_supplier_quotes (tenant_id, rfq_id, id)
    ON DELETE RESTRICT
    """
  end

  defp identity_indexes(table) do
    create unique_index(table, [:tenant_id, :id])

    create constraint(table, String.to_atom("#{table}_identifier_check"),
             check: "stable_identifier ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{2,99}$'"
           )
  end

  defp positive_version(table) do
    create constraint(table, String.to_atom("#{table}_version_check"), check: "lock_version > 0")
  end

  defp tenant_fk(table, column, referenced_table) do
    execute """
    ALTER TABLE #{table}
    ADD CONSTRAINT #{table}_tenant_#{column}_fkey
    FOREIGN KEY (tenant_id, #{column})
    REFERENCES #{referenced_table} (tenant_id, id)
    ON DELETE RESTRICT
    """
  end

  defp enable_tenant_isolation do
    for table <- @tables do
      execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY"
      execute "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY"

      execute """
      CREATE POLICY #{table}_tenant_isolation ON #{table}
      USING (tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid)
      WITH CHECK (tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid)
      """
    end
  end
end
