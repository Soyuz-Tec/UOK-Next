\set ON_ERROR_STOP on

SELECT format('ALTER ROLE %I PASSWORD %L', current_user, :'admin_password')
\gexec
