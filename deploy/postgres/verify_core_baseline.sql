\set ON_ERROR_STOP on

DO $uok_baseline$
DECLARE
  database_record record;
  version_number integer := current_setting('server_version_num')::integer;
BEGIN
  IF version_number < 190000 OR version_number >= 200000 THEN
    RAISE EXCEPTION 'PostgreSQL major 19 is required; server_version_num=%', version_number;
  END IF;

  IF current_setting('data_checksums') <> 'on' THEN
    RAISE EXCEPTION 'data checksums must be enabled';
  END IF;

  IF current_setting('password_encryption') <> 'scram-sha-256' THEN
    RAISE EXCEPTION 'password_encryption must be scram-sha-256';
  END IF;

  IF current_setting('fsync') <> 'on' OR
     current_setting('full_page_writes') <> 'on' OR
     current_setting('synchronous_commit') <> 'on' THEN
    RAISE EXCEPTION 'PostgreSQL durability controls must remain enabled';
  END IF;

  IF current_setting('autovacuum') <> 'on' THEN
    RAISE EXCEPTION 'autovacuum must remain enabled';
  END IF;

  IF current_setting('TimeZone') NOT IN ('UTC', 'Etc/UTC', 'GMT') THEN
    RAISE EXCEPTION 'database timezone must be UTC';
  END IF;

  SELECT
    pg_encoding_to_char(encoding) AS encoding,
    datlocprovider,
    datlocale
  INTO STRICT database_record
  FROM pg_database
  WHERE datname = current_database();

  IF database_record.encoding <> 'UTF8' OR
     database_record.datlocprovider <> 'b' OR
     database_record.datlocale <> 'PG_UNICODE_FAST' THEN
    RAISE EXCEPTION
      'database identity must be UTF8/builtin/PG_UNICODE_FAST; got %/%/%',
      database_record.encoding,
      database_record.datlocprovider,
      database_record.datlocale;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_extension
    WHERE extname NOT IN ('plpgsql', 'pg_stat_statements')
  ) THEN
    RAISE EXCEPTION 'an extension outside the database policy allowlist is installed';
  END IF;
END
$uok_baseline$;
