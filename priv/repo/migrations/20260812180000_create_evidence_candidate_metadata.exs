defmodule UokNext.Repo.Migrations.CreateEvidenceCandidateMetadata do
  use Ecto.Migration

  def up do
    create table(:platform_evidence_objects, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :subject_type, :string, null: false, size: 120
      add :subject_id, :uuid, null: false
      add :content_type, :string, null: false, size: 120
      add :byte_size, :bigint, null: false
      add :sha256, :string, null: false, size: 64
      add :object_key, :string, null: false, size: 512
      add :classification, :string, null: false, size: 32
      add :state, :string, null: false, size: 32, default: "pending_upload"
      add :storage_receipt, :map
      add :verified_at, :utc_datetime_usec
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:platform_evidence_objects, [:tenant_id, :id],
             name: :platform_evidence_objects_tenant_identity_index
           )

    create unique_index(:platform_evidence_objects, [:object_key],
             name: :platform_evidence_objects_object_key_index
           )

    create index(:platform_evidence_objects, [:tenant_id, :subject_type, :subject_id],
             name: :platform_evidence_objects_subject_index
           )

    create constraint(:platform_evidence_objects, :platform_evidence_objects_subject_type_check,
             check: "subject_type ~ '^[a-z][a-z0-9_.:-]{1,119}$'"
           )

    create constraint(:platform_evidence_objects, :platform_evidence_objects_content_type_check,
             check:
               "content_type IN ('application/octet-stream', 'application/pdf', 'image/jpeg', 'image/png', 'text/plain')"
           )

    create constraint(:platform_evidence_objects, :platform_evidence_objects_size_check,
             check: "byte_size BETWEEN 1 AND 8388608"
           )

    create constraint(:platform_evidence_objects, :platform_evidence_objects_sha256_check,
             check: "sha256 ~ '^[0-9a-f]{64}$'"
           )

    create constraint(:platform_evidence_objects, :platform_evidence_objects_classification_check,
             check: "classification IN ('public', 'internal', 'confidential', 'restricted')"
           )

    create constraint(:platform_evidence_objects, :platform_evidence_objects_state_check,
             check: "state IN ('pending_upload', 'verified')"
           )

    create constraint(:platform_evidence_objects, :platform_evidence_objects_version_check,
             check: "lock_version > 0"
           )

    create constraint(:platform_evidence_objects, :platform_evidence_objects_lifecycle_check,
             check: """
             (state = 'pending_upload' AND storage_receipt IS NULL AND verified_at IS NULL) OR
             (state = 'verified' AND storage_receipt IS NOT NULL AND verified_at IS NOT NULL)
             """
           )

    execute "ALTER TABLE platform_evidence_objects ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE platform_evidence_objects FORCE ROW LEVEL SECURITY"

    execute """
    CREATE POLICY platform_evidence_objects_tenant_isolation
    ON platform_evidence_objects
    USING (tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid)
    WITH CHECK (tenant_id = NULLIF(current_setting('uok.tenant_id', true), '')::uuid)
    """
  end

  def down do
    execute "DROP POLICY IF EXISTS platform_evidence_objects_tenant_isolation ON platform_evidence_objects"
    drop table(:platform_evidence_objects)
  end
end
