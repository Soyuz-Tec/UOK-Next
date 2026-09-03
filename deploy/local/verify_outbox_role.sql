\set ON_ERROR_STOP on

DO $$
DECLARE
  worker_role pg_roles%ROWTYPE;
BEGIN
  SELECT * INTO STRICT worker_role FROM pg_roles WHERE rolname = 'uok_outbox';

  IF worker_role.rolsuper OR worker_role.rolbypassrls OR worker_role.rolreplication OR
     worker_role.rolcreatedb OR worker_role.rolcreaterole OR worker_role.rolinherit OR
     worker_role.rolconfig IS NOT NULL OR worker_role.rolconnlimit <> 8 THEN
    RAISE EXCEPTION 'uok_outbox retains an unsafe role attribute or setting';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_auth_members membership
    JOIN pg_roles member_role ON member_role.oid = membership.member
    JOIN pg_roles granted_role ON granted_role.oid = membership.roleid
    WHERE member_role.rolname = 'uok_outbox' OR granted_role.rolname = 'uok_outbox'
  ) THEN
    RAISE EXCEPTION 'uok_outbox retains an unexpected role membership';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_stat_activity
    WHERE datname = current_database()
      AND backend_type = 'client backend'
      AND usename = 'uok_outbox'
  ) THEN
    RAISE EXCEPTION 'a stale durable-work session survived role reconciliation';
  END IF;

  IF NOT has_database_privilege('uok_outbox', current_database(), 'CONNECT') OR
     NOT has_schema_privilege('uok_outbox', 'public', 'USAGE') THEN
    RAISE EXCEPTION 'uok_outbox is missing connection or schema privilege';
  END IF;
END
$$;

DO $$
DECLARE
  unexpected_privileges integer;
BEGIN
  IF NOT (
    has_table_privilege('uok_outbox', 'public.kernel_outbox_events', 'SELECT,UPDATE') AND
    has_table_privilege('uok_outbox', 'public.kernel_durable_jobs', 'SELECT,INSERT,UPDATE') AND
    has_table_privilege('uok_outbox', 'public.kernel_outbox_deliveries', 'SELECT,INSERT')
  ) THEN
    RAISE EXCEPTION 'uok_outbox is missing an expected table privilege';
  END IF;

  SELECT count(*) INTO unexpected_privileges
  FROM information_schema.role_table_grants
  WHERE grantee = 'uok_outbox'
    AND (table_schema, table_name, privilege_type) NOT IN (
      ('public', 'kernel_outbox_events', 'SELECT'),
      ('public', 'kernel_outbox_events', 'UPDATE'),
      ('public', 'kernel_durable_jobs', 'SELECT'),
      ('public', 'kernel_durable_jobs', 'INSERT'),
      ('public', 'kernel_durable_jobs', 'UPDATE'),
      ('public', 'kernel_outbox_deliveries', 'SELECT'),
      ('public', 'kernel_outbox_deliveries', 'INSERT')
    );

  IF unexpected_privileges > 0 THEN
    RAISE EXCEPTION 'uok_outbox retains unexpected table privileges';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.role_usage_grants
    WHERE grantee = 'uok_outbox' AND object_type = 'SEQUENCE'
  ) THEN
    RAISE EXCEPTION 'uok_outbox retains unexpected sequence privileges';
  END IF;
END
$$;
