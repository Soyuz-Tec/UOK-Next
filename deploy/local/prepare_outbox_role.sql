\set ON_ERROR_STOP on

SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = current_database()
  AND backend_type = 'client backend'
  AND usename = 'uok_outbox'
  AND pid <> pg_backend_pid();

SELECT format(
  'CREATE ROLE uok_outbox LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS NOREPLICATION CONNECTION LIMIT 8 PASSWORD %L',
  :'outbox_password'
)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'uok_outbox')
\gexec

SELECT format(
  'ALTER ROLE uok_outbox LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS NOREPLICATION CONNECTION LIMIT 8 PASSWORD %L',
  :'outbox_password'
)
\gexec

ALTER ROLE uok_outbox RESET ALL;

SELECT format('REVOKE %I FROM uok_outbox', granted_role.rolname)
FROM pg_auth_members membership
JOIN pg_roles member_role ON member_role.oid = membership.member
JOIN pg_roles granted_role ON granted_role.oid = membership.roleid
WHERE member_role.rolname = 'uok_outbox'
\gexec

SELECT format('REVOKE uok_outbox FROM %I', member_role.rolname)
FROM pg_auth_members membership
JOIN pg_roles member_role ON member_role.oid = membership.member
JOIN pg_roles granted_role ON granted_role.oid = membership.roleid
WHERE granted_role.rolname = 'uok_outbox'
\gexec

SELECT format('GRANT CONNECT ON DATABASE %I TO uok_outbox', current_database())
\gexec
GRANT USAGE ON SCHEMA public TO uok_outbox;
