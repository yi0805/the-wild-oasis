-- Task 033: install the daily recruiter-demo reset schedule.
--
-- Apply manually in the hosted Supabase SQL Editor only after the pg_cron
-- integration has been enabled. The project intentionally has unreconciled
-- CLI migration history, so do not use `supabase db push` for this file.
--
-- This script schedules the reset but does not invoke it. The first reset is
-- due at the next 00:05 UTC boundary after installation.

BEGIN;

DO $install_recruiter_demo_daily_reset$
DECLARE
  expected_job_name constant text := 'recruiter-demo-daily-reset';
  expected_schedule constant text := '5 0 * * *';
  expected_command constant text := 'SELECT private.reset_recruiter_demo_data();';
  expected_function_definition_md5 constant text :=
    '35c5fa5e72f7fe192c64fd75dc077f3e';
  reset_function_oid oid;
  reset_function_owner name;
  reset_is_security_definer boolean;
  reset_configuration text[];
  reset_definition_md5 text;
  matching_name_count integer;
  reset_command_count integer;
  scheduled_job_id bigint;
  stored_job record;
BEGIN
  SELECT
    procedure.oid,
    owner_role.rolname,
    procedure.prosecdef,
    procedure.proconfig,
    md5(pg_get_functiondef(procedure.oid))
  INTO
    reset_function_oid,
    reset_function_owner,
    reset_is_security_definer,
    reset_configuration,
    reset_definition_md5
  FROM pg_proc AS procedure
  JOIN pg_namespace AS function_schema
    ON function_schema.oid = procedure.pronamespace
  JOIN pg_roles AS owner_role
    ON owner_role.oid = procedure.proowner
  JOIN pg_language AS function_language
    ON function_language.oid = procedure.prolang
  WHERE function_schema.nspname = 'private'
    AND procedure.proname = 'reset_recruiter_demo_data'
    AND pg_get_function_identity_arguments(procedure.oid) = ''
    AND pg_get_function_result(procedure.oid) = 'void'
    AND function_language.lanname = 'plpgsql';

  IF reset_function_oid IS NULL THEN
    RAISE EXCEPTION
      'Cron installation refused: expected private.reset_recruiter_demo_data() was not found';
  END IF;

  IF reset_definition_md5 <> expected_function_definition_md5 THEN
    RAISE EXCEPTION
      'Cron installation refused: reset function definition does not match the reviewed Task 032 function';
  END IF;

  IF reset_is_security_definer THEN
    RAISE EXCEPTION
      'Cron installation refused: reset function must remain SECURITY INVOKER';
  END IF;

  IF reset_configuration IS DISTINCT FROM
    ARRAY['search_path=pg_catalog, public']::text[]
  THEN
    RAISE EXCEPTION
      'Cron installation refused: reset function search_path is not locked to pg_catalog, public';
  END IF;

  IF EXISTS (
      SELECT 1
      FROM aclexplode(
        COALESCE(
          (SELECT namespace.nspacl
           FROM pg_namespace AS namespace
           WHERE namespace.nspname = 'private'),
          acldefault(
            'n',
            (SELECT namespace.nspowner
             FROM pg_namespace AS namespace
             WHERE namespace.nspname = 'private')
          )
        )
      ) AS schema_acl
      WHERE schema_acl.grantee = 0
        AND schema_acl.privilege_type = 'USAGE'
    )
    OR has_schema_privilege('anon', 'private', 'USAGE')
    OR has_schema_privilege('authenticated', 'private', 'USAGE')
  THEN
    RAISE EXCEPTION
      'Cron installation refused: a browser role can use the private schema';
  END IF;

  IF EXISTS (
      SELECT 1
      FROM pg_proc AS procedure
      CROSS JOIN LATERAL aclexplode(
        COALESCE(procedure.proacl, acldefault('f', procedure.proowner))
      ) AS function_acl
      WHERE procedure.oid = reset_function_oid
        AND function_acl.grantee = 0
        AND function_acl.privilege_type = 'EXECUTE'
    )
    OR has_function_privilege(
      'anon',
      reset_function_oid,
      'EXECUTE'
    )
    OR has_function_privilege(
      'authenticated',
      reset_function_oid,
      'EXECUTE'
    )
  THEN
    RAISE EXCEPTION
      'Cron installation refused: a browser role can execute the reset function';
  END IF;

  IF current_user <> reset_function_owner THEN
    RAISE EXCEPTION
      'Cron installation refused: installer role % must match reset owner %',
      current_user,
      reset_function_owner;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_extension
    WHERE extname = 'pg_cron'
  ) THEN
    RAISE EXCEPTION
      'Cron installation refused: enable the hosted pg_cron integration first';
  END IF;

  IF to_regclass('cron.job') IS NULL
    OR to_regclass('cron.job_run_details') IS NULL
    OR to_regprocedure('cron.schedule(text,text,text)') IS NULL
    OR to_regprocedure('cron.unschedule(text)') IS NULL
  THEN
    RAISE EXCEPTION
      'Cron installation refused: required pg_cron objects are unavailable';
  END IF;

  IF EXISTS (
      SELECT 1
      FROM pg_namespace AS cron_schema
      CROSS JOIN LATERAL aclexplode(
        COALESCE(
          cron_schema.nspacl,
          acldefault('n', cron_schema.nspowner)
        )
      ) AS schema_acl
      WHERE cron_schema.nspname = 'cron'
        AND schema_acl.grantee = 0
        AND schema_acl.privilege_type = 'USAGE'
    )
    OR has_schema_privilege('anon', 'cron', 'USAGE')
    OR has_schema_privilege('authenticated', 'cron', 'USAGE')
  THEN
    RAISE EXCEPTION
      'Cron installation refused: a browser role can use the cron schema';
  END IF;

  IF current_setting('cron.timezone', true) NOT IN ('GMT', 'UTC') THEN
    RAISE EXCEPTION
      'Cron installation refused: cron.timezone must be GMT or UTC, found %',
      current_setting('cron.timezone', true);
  END IF;

  IF current_setting('cron.database_name', true) IS DISTINCT FROM
    current_database()
  THEN
    RAISE EXCEPTION
      'Cron installation refused: pg_cron targets database %, current database is %',
      current_setting('cron.database_name', true),
      current_database();
  END IF;

  IF current_setting('cron.enable_superuser_jobs', true) <> 'on'
    AND EXISTS (
      SELECT 1
      FROM pg_roles
      WHERE rolname = current_user
        AND rolsuper
    )
  THEN
    RAISE EXCEPTION
      'Cron installation refused: pg_cron is configured to reject the current superuser role';
  END IF;

  IF (statement_timestamp() AT TIME ZONE 'UTC')::time >= time '00:04'
    AND (statement_timestamp() AT TIME ZONE 'UTC')::time < time '00:07'
  THEN
    RAISE EXCEPTION
      'Cron installation refused: apply outside 00:04-00:07 UTC to avoid the scheduled boundary';
  END IF;

  EXECUTE
    'SELECT count(*) FROM cron.job WHERE jobname = $1'
  INTO matching_name_count
  USING expected_job_name;

  IF matching_name_count <> 0 THEN
    RAISE EXCEPTION
      'Cron installation refused: job name % already exists',
      expected_job_name;
  END IF;

  EXECUTE
    $query$
      SELECT count(*)
      FROM cron.job
      WHERE position(
        'private.reset_recruiter_demo_data'
        IN lower(command)
      ) > 0
    $query$
  INTO reset_command_count;

  IF reset_command_count <> 0 THEN
    RAISE EXCEPTION
      'Cron installation refused: another job already targets the recruiter reset function';
  END IF;

  EXECUTE 'SELECT cron.schedule($1, $2, $3)'
  INTO scheduled_job_id
  USING expected_job_name, expected_schedule, expected_command;

  EXECUTE
    $query$
      SELECT
        jobid,
        jobname,
        schedule,
        command,
        database,
        username,
        active
      FROM cron.job
      WHERE jobid = $1
    $query$
  INTO stored_job
  USING scheduled_job_id;

  IF NOT FOUND
    OR stored_job.jobname IS DISTINCT FROM expected_job_name
    OR stored_job.schedule IS DISTINCT FROM expected_schedule
    OR stored_job.command IS DISTINCT FROM expected_command
    OR stored_job.database IS DISTINCT FROM current_database()
    OR stored_job.username IS DISTINCT FROM current_user
    OR stored_job.active IS DISTINCT FROM true
  THEN
    RAISE EXCEPTION
      'Cron installation verification failed: stored job metadata is unexpected';
  END IF;

  EXECUTE
    $query$
      SELECT count(*)
      FROM cron.job
      WHERE jobname = $1
        OR position(
          'private.reset_recruiter_demo_data'
          IN lower(command)
        ) > 0
    $query$
  INTO reset_command_count
  USING expected_job_name;

  IF reset_command_count <> 1 THEN
    RAISE EXCEPTION
      'Cron installation verification failed: expected exactly one reset job';
  END IF;
END
$install_recruiter_demo_daily_reset$;

COMMIT;

-- Reviewed rollback / unschedule procedure
--
-- Run the block below separately in the hosted SQL Editor. It refuses to
-- remove a same-named job unless its schedule, command, database, and execution
-- role still match this installation. It is intentionally commented out so it
-- cannot run during installation.
--
-- BEGIN;
-- DO $remove_recruiter_demo_daily_reset$
-- DECLARE
--   expected_job_name constant text := 'recruiter-demo-daily-reset';
--   expected_schedule constant text := '5 0 * * *';
--   expected_command constant text :=
--     'SELECT private.reset_recruiter_demo_data();';
--   matched_job record;
--   removed boolean;
-- BEGIN
--   IF to_regclass('cron.job') IS NULL
--     OR to_regprocedure('cron.unschedule(text)') IS NULL
--   THEN
--     RAISE EXCEPTION
--       'Cron rollback refused: required pg_cron objects are unavailable';
--   END IF;
--
--   EXECUTE
--     'SELECT jobid, jobname, schedule, command, database, username
--      FROM cron.job
--      WHERE jobname = $1'
--   INTO STRICT matched_job
--   USING expected_job_name;
--
--   IF matched_job.schedule IS DISTINCT FROM expected_schedule
--     OR matched_job.command IS DISTINCT FROM expected_command
--     OR matched_job.database IS DISTINCT FROM current_database()
--     OR matched_job.username IS DISTINCT FROM current_user
--   THEN
--     RAISE EXCEPTION
--       'Cron rollback refused: same-named job metadata is unexpected';
--   END IF;
--
--   EXECUTE 'SELECT cron.unschedule($1)'
--   INTO removed
--   USING expected_job_name;
--
--   IF removed IS DISTINCT FROM true THEN
--     RAISE EXCEPTION
--       'Cron rollback failed: pg_cron did not remove the expected job';
--   END IF;
--
--   EXECUTE
--     'SELECT EXISTS (SELECT 1 FROM cron.job WHERE jobname = $1)'
--   INTO removed
--   USING expected_job_name;
--
--   IF removed THEN
--     RAISE EXCEPTION
--       'Cron rollback failed: expected job still exists';
--   END IF;
-- END
-- $remove_recruiter_demo_daily_reset$;
-- COMMIT;
