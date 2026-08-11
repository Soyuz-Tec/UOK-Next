\set ON_ERROR_STOP on

-- This file runs only while the local PG19 qualification cluster is first
-- initialized. Production platforms must express the same contract in their
-- own reviewed infrastructure code rather than replaying a container fixture.
SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', current_database())
\gexec

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA public FROM PUBLIC;

ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON ROUTINES FROM PUBLIC;

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Extension installation can create routines with PostgreSQL's broad default
-- EXECUTE privilege. Monitoring is granted deliberately by the platform later.
REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA public FROM PUBLIC;
