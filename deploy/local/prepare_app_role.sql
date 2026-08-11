\set ON_ERROR_STOP on

-- Prevent a previously authorized client from surviving credential and role
-- reconciliation. The local qualification owner is a superuser, so it can
-- recover a fail-closed connection limit on the next run if this script stops.
SELECT format('ALTER DATABASE %I CONNECTION LIMIT 0', current_database())
\gexec

SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = current_database()
  AND backend_type = 'client backend'
  AND pid <> pg_backend_pid();

SELECT format(
  'CREATE ROLE uok_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS NOREPLICATION PASSWORD %L',
  :'app_password'
)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'uok_app')
\gexec

SELECT format(
  'ALTER ROLE uok_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS NOREPLICATION PASSWORD %L',
  :'app_password'
)
\gexec

ALTER ROLE uok_app RESET ALL;

SELECT format('REVOKE %I FROM uok_app', granted_role.rolname)
FROM pg_auth_members membership
JOIN pg_roles member_role ON member_role.oid = membership.member
JOIN pg_roles granted_role ON granted_role.oid = membership.roleid
WHERE member_role.rolname = 'uok_app'
\gexec

SELECT format('REVOKE uok_app FROM %I', member_role.rolname)
FROM pg_auth_members membership
JOIN pg_roles member_role ON member_role.oid = membership.member
JOIN pg_roles granted_role ON granted_role.oid = membership.roleid
WHERE granted_role.rolname = 'uok_app'
\gexec

SELECT format('GRANT CONNECT ON DATABASE %I TO uok_app', current_database())
\gexec
GRANT USAGE ON SCHEMA public TO uok_app;

SELECT format('ALTER DATABASE %I CONNECTION LIMIT -1', current_database())
\gexec
