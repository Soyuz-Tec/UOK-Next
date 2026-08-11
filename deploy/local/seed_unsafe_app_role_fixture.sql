\set ON_ERROR_STOP on

SELECT 'CREATE ROLE uok_qualification_poison LOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'uok_qualification_poison')
\gexec

ALTER ROLE uok_qualification_poison LOGIN;
ALTER ROLE uok_app BYPASSRLS REPLICATION INHERIT CONNECTION LIMIT -1;
ALTER ROLE uok_app SET statement_timeout = '0';
GRANT pg_read_all_data TO uok_app;
GRANT uok_app TO uok_qualification_poison;
