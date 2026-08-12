\set ON_ERROR_STOP on

DO $$
DECLARE
  runtime_role pg_roles%ROWTYPE;
BEGIN
  SELECT * INTO STRICT runtime_role FROM pg_roles WHERE rolname = 'uok_app';

  IF runtime_role.rolsuper OR runtime_role.rolbypassrls OR runtime_role.rolreplication OR
     runtime_role.rolcreatedb OR runtime_role.rolcreaterole OR runtime_role.rolinherit OR
     runtime_role.rolconfig IS NOT NULL OR runtime_role.rolconnlimit <> 20 THEN
    RAISE EXCEPTION 'uok_app retains an unsafe role attribute or setting';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_auth_members membership
    JOIN pg_roles member_role ON member_role.oid = membership.member
    JOIN pg_roles granted_role ON granted_role.oid = membership.roleid
    WHERE member_role.rolname = 'uok_app' OR granted_role.rolname = 'uok_app'
  ) THEN
    RAISE EXCEPTION 'uok_app retains an unexpected role membership';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_stat_activity
    WHERE datname = current_database()
      AND backend_type = 'client backend'
      AND usename IN ('uok_app', 'uok_qualification_poison')
  ) THEN
    RAISE EXCEPTION 'a stale runtime-authorized database session survived reconciliation';
  END IF;

  IF (SELECT datconnlimit FROM pg_database WHERE datname = current_database()) <> -1 THEN
    RAISE EXCEPTION 'the qualification database connection limit was not restored';
  END IF;

  IF NOT has_database_privilege('uok_app', current_database(), 'CONNECT') OR
     NOT has_schema_privilege('uok_app', 'public', 'USAGE') THEN
    RAISE EXCEPTION 'uok_app is missing a required connection or schema privilege';
  END IF;
END
$$;

DO $$
DECLARE
  unexpected_privileges integer;
BEGIN
  IF NOT (
    has_table_privilege('uok_app', 'public.schema_migrations', 'SELECT') AND
    has_table_privilege('uok_app', 'public.kernel_command_receipts', 'SELECT,INSERT,UPDATE') AND
    has_table_privilege('uok_app', 'public.kernel_audit_events', 'SELECT,INSERT') AND
    has_table_privilege('uok_app', 'public.kernel_outbox_events', 'SELECT,INSERT') AND
    has_table_privilege('uok_app', 'public.master_parties', 'SELECT,INSERT,UPDATE') AND
    has_table_privilege('uok_app', 'public.master_products', 'SELECT,INSERT') AND
    has_table_privilege('uok_app', 'public.master_locations', 'SELECT,INSERT') AND
    has_table_privilege('uok_app', 'public.trade_sourcing_lanes', 'SELECT,INSERT,UPDATE') AND
    has_table_privilege('uok_app', 'public.platform_workflow_human_tasks', 'SELECT,INSERT,UPDATE') AND
    has_table_privilege('uok_app', 'public.platform_integrations_connector_receipts', 'SELECT,INSERT,UPDATE') AND
    has_table_privilege('uok_app', 'public.platform_agents_plans', 'SELECT,INSERT,UPDATE') AND
    has_table_privilege('uok_app', 'public.platform_evidence_objects', 'SELECT,INSERT,UPDATE')
  ) THEN
    RAISE EXCEPTION 'uok_app is missing an expected table privilege';
  END IF;

  SELECT count(*) INTO unexpected_privileges
  FROM information_schema.role_table_grants
  WHERE grantee = 'uok_app'
    AND (table_schema, table_name, privilege_type) NOT IN (
      ('public', 'schema_migrations', 'SELECT'),
      ('public', 'kernel_command_receipts', 'SELECT'),
      ('public', 'kernel_command_receipts', 'INSERT'),
      ('public', 'kernel_command_receipts', 'UPDATE'),
      ('public', 'kernel_audit_events', 'SELECT'),
      ('public', 'kernel_audit_events', 'INSERT'),
      ('public', 'kernel_outbox_events', 'SELECT'),
      ('public', 'kernel_outbox_events', 'INSERT'),
      ('public', 'master_parties', 'SELECT'),
      ('public', 'master_parties', 'INSERT'),
      ('public', 'master_parties', 'UPDATE'),
      ('public', 'master_products', 'SELECT'),
      ('public', 'master_products', 'INSERT'),
      ('public', 'master_locations', 'SELECT'),
      ('public', 'master_locations', 'INSERT'),
      ('public', 'trade_sourcing_lanes', 'SELECT'),
      ('public', 'trade_sourcing_lanes', 'INSERT'),
      ('public', 'trade_sourcing_lanes', 'UPDATE'),
      ('public', 'platform_workflow_human_tasks', 'SELECT'),
      ('public', 'platform_workflow_human_tasks', 'INSERT'),
      ('public', 'platform_workflow_human_tasks', 'UPDATE'),
      ('public', 'platform_integrations_connector_receipts', 'SELECT'),
      ('public', 'platform_integrations_connector_receipts', 'INSERT'),
      ('public', 'platform_integrations_connector_receipts', 'UPDATE'),
      ('public', 'platform_agents_plans', 'SELECT'),
      ('public', 'platform_agents_plans', 'INSERT'),
      ('public', 'platform_agents_plans', 'UPDATE'),
      ('public', 'platform_evidence_objects', 'SELECT'),
      ('public', 'platform_evidence_objects', 'INSERT'),
      ('public', 'platform_evidence_objects', 'UPDATE')
    );

  IF unexpected_privileges > 0 THEN
    RAISE EXCEPTION 'uok_app retains unexpected table privileges';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.role_usage_grants
    WHERE grantee = 'uok_app' AND object_type = 'SEQUENCE'
  ) THEN
    RAISE EXCEPTION 'uok_app retains unexpected sequence privileges';
  END IF;
END
$$;
