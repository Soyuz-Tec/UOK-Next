\set ON_ERROR_STOP on
\ir verify_core_baseline.sql

DO $uok_local_platform$
DECLARE
  preload_libraries text := current_setting('shared_preload_libraries');
BEGIN
  IF NOT ('pg_stat_statements' = ANY (string_to_array(preload_libraries, ','))) THEN
    RAISE EXCEPTION 'pg_stat_statements must be preloaded';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements') THEN
    RAISE EXCEPTION 'pg_stat_statements must be installed';
  END IF;

  IF current_setting('compute_query_id') NOT IN ('on', 'auto') OR
     current_setting('track_io_timing') <> 'on' OR
     current_setting('track_wal_io_timing') <> 'on' THEN
    RAISE EXCEPTION 'query identifiers and database/WAL I/O timing must be enabled';
  END IF;

  IF current_setting('log_lock_waits') <> 'on' OR
     (SELECT setting::integer FROM pg_settings WHERE name = 'log_min_duration_statement') <> 500 OR
     (SELECT setting::integer FROM pg_settings WHERE name = 'log_autovacuum_min_duration') <> 1000 THEN
    RAISE EXCEPTION 'bounded slow-query, lock-wait, and autovacuum logging is required';
  END IF;

  IF current_setting('max_connections')::integer <> 50 OR
     current_setting('reserved_connections')::integer <> 5 OR
     current_setting('superuser_reserved_connections')::integer <> 3 THEN
    RAISE EXCEPTION 'the local connection budget has drifted';
  END IF;

  IF has_schema_privilege('public', 'public', 'CREATE') OR
     has_database_privilege('public', current_database(), 'CONNECT') THEN
    RAISE EXCEPTION 'PUBLIC retains broad schema creation or database connection';
  END IF;
END
$uok_local_platform$;
