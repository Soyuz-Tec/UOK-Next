\set ON_ERROR_STOP on

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
