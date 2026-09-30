-- Task 033 read-only hosted verification.
--
-- Run only after enabling pg_cron and manually applying the reviewed schedule
-- file. This script never invokes the reset and never changes Cron, Auth, or
-- application data. An empty run-history result means the scheduler has not yet
-- produced evidence; it is not evidence of a successful scheduled run.

-- 1. Cron capability and UTC scheduling context.
SELECT
  current_database() AS current_database,
  current_user AS inspection_role,
  extension.extversion AS pg_cron_version,
  current_setting('cron.timezone', true) AS cron_timezone,
  current_setting('cron.database_name', true) AS cron_database_name,
  current_setting('cron.use_background_workers', true) AS cron_uses_workers,
  current_setting('cron.enable_superuser_jobs', true) AS cron_allows_superuser_jobs,
  EXISTS (
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
  ) AS public_can_use_cron_schema,
  has_schema_privilege('anon', 'cron', 'USAGE')
    AS anon_can_use_cron_schema,
  has_schema_privilege('authenticated', 'cron', 'USAGE')
    AS authenticated_can_use_cron_schema
FROM pg_extension AS extension
WHERE extension.extname = 'pg_cron';

-- 2. Exact intended job. Expect one row with postgres as username, postgres as
-- database, active = true, schedule 5 0 * * *, and the exact direct command.
SELECT
  jobid,
  jobname,
  schedule,
  command,
  database,
  username AS execution_role,
  active
FROM cron.job
WHERE jobname = 'recruiter-demo-daily-reset';

-- 3. Duplicate/conflict summary. Expect all counts to be one, except
-- unexpected_reset_job_count which must be zero.
SELECT
  count(*) FILTER (
    WHERE jobname = 'recruiter-demo-daily-reset'
  ) AS intended_name_count,
  count(*) FILTER (
    WHERE jobname = 'recruiter-demo-daily-reset'
      AND schedule = '5 0 * * *'
      AND command = 'SELECT private.reset_recruiter_demo_data();'
      AND database = current_database()
      AND username = 'postgres'
      AND active
  ) AS exact_active_job_count,
  count(*) FILTER (
    WHERE position(
      'private.reset_recruiter_demo_data'
      IN lower(command)
    ) > 0
  ) AS all_reset_job_count,
  count(*) FILTER (
    WHERE position(
      'private.reset_recruiter_demo_data'
      IN lower(command)
    ) > 0
      AND jobname <> 'recruiter-demo-daily-reset'
  ) AS unexpected_reset_job_count
FROM cron.job;

-- 4. Recent scheduler evidence. Do not claim a scheduler success until this
-- returns a status = succeeded row whose command and timestamps belong to the
-- intended job. The result is ordered newest first.
SELECT
  run.runid,
  run.jobid,
  job.jobname,
  run.database,
  run.username AS execution_role,
  run.command,
  run.status,
  run.return_message,
  run.start_time,
  run.end_time
FROM cron.job_run_details AS run
JOIN cron.job AS job
  ON job.jobid = run.jobid
WHERE job.jobname = 'recruiter-demo-daily-reset'
ORDER BY run.start_time DESC NULLS LAST, run.runid DESC
LIMIT 10;

-- 5. Task 032 function identity and browser-role boundary. Expect one row,
-- definition MD5 35c5fa5e72f7fe192c64fd75dc077f3e, postgres ownership,
-- security_definer = false, the locked search_path, and every privilege flag
-- below = false.
SELECT
  owner_role.rolname AS function_owner,
  pg_get_function_result(procedure.oid) AS result_type,
  function_language.lanname AS language_name,
  procedure.prosecdef AS security_definer,
  procedure.proconfig AS function_configuration,
  md5(pg_get_functiondef(procedure.oid)) AS function_definition_md5,
  EXISTS (
    SELECT 1
    FROM aclexplode(
      COALESCE(
        function_schema.nspacl,
        acldefault('n', function_schema.nspowner)
      )
    ) AS schema_acl
    WHERE schema_acl.grantee = 0
      AND schema_acl.privilege_type = 'USAGE'
  ) AS public_can_use_private_schema,
  has_schema_privilege('anon', function_schema.oid, 'USAGE')
    AS anon_can_use_private_schema,
  has_schema_privilege('authenticated', function_schema.oid, 'USAGE')
    AS authenticated_can_use_private_schema,
  EXISTS (
    SELECT 1
    FROM aclexplode(
      COALESCE(procedure.proacl, acldefault('f', procedure.proowner))
    ) AS function_acl
    WHERE function_acl.grantee = 0
      AND function_acl.privilege_type = 'EXECUTE'
  ) AS public_can_execute_reset,
  has_function_privilege('anon', procedure.oid, 'EXECUTE')
    AS anon_can_execute_reset,
  has_function_privilege('authenticated', procedure.oid, 'EXECUTE')
    AS authenticated_can_execute_reset
FROM pg_proc AS procedure
JOIN pg_namespace AS function_schema
  ON function_schema.oid = procedure.pronamespace
JOIN pg_roles AS owner_role
  ON owner_role.oid = procedure.proowner
JOIN pg_language AS function_language
  ON function_language.oid = procedure.prolang
WHERE function_schema.nspname = 'private'
  AND procedure.proname = 'reset_recruiter_demo_data'
  AND pg_get_function_identity_arguments(procedure.oid) = '';

-- 6. Canonical dataset and UTC Today Activity. Immediately after a successful
-- scheduled run expect 8/24/24, one settings row, queue zero, settings 3/90/8/15,
-- and Today Activity 2 arrivals / 2 departures.
SELECT
  statement_timestamp() AT TIME ZONE 'UTC' AS inspected_at_utc,
  (SELECT count(*) FROM public.cabins) AS cabin_count,
  (SELECT count(*) FROM public.guests) AS guest_count,
  (SELECT count(*) FROM public.bookings) AS booking_count,
  (SELECT count(*) FROM public.settings) AS settings_count,
  (SELECT count(*) FROM public.cabin_image_cleanup_queue)
    AS cleanup_queue_count,
  (SELECT count(*)
   FROM public.bookings
   WHERE status = 'unconfirmed'
     AND ("startDate" AT TIME ZONE 'UTC')::date =
       (statement_timestamp() AT TIME ZONE 'UTC')::date)
    AS today_arrivals,
  (SELECT count(*)
   FROM public.bookings
   WHERE status = 'checked-in'
     AND ("endDate" AT TIME ZONE 'UTC')::date =
       (statement_timestamp() AT TIME ZONE 'UTC')::date)
    AS today_departures,
  (SELECT json_build_object(
      'id', id,
      'minBookingLength', "minBookingLength",
      'maxBookingLength', "maxBookingLength",
      'maxGuestsPerBooking', "maxGuestsPerBooking",
      'breakfastPrice', "breakfastPrice"
    )
   FROM public.settings
   WHERE id = 1) AS settings;

-- 7. Compact dataset marker/integrity summary. Expect all three marked counts
-- to match the total counts above and every invalid count to be zero. Run the
-- existing Task 032 post-apply verification as well for the complete canonical
-- distribution, arithmetic, overlap, image, Auth/avatar, and cleanup checks.
SELECT
  count(*) FILTER (
    WHERE demo_dataset = 'recruiter-v1'
  ) AS marked_booking_count,
  count(*) FILTER (
    WHERE demo_dataset IS DISTINCT FROM 'recruiter-v1'
  ) AS unmarked_booking_count,
  count(*) FILTER (
    WHERE "guestId" IS NULL OR "cabinId" IS NULL
  ) AS booking_missing_foreign_key_count,
  count(*) FILTER (
    WHERE "startDate" IS NULL
      OR "endDate" IS NULL
      OR "startDate" >= "endDate"
      OR "numNights" < 1
      OR "numGuests" < 1
      OR status NOT IN ('unconfirmed', 'checked-in', 'checked-out')
  ) AS invalid_booking_count
FROM public.bookings;

SELECT
  (SELECT count(*)
   FROM public.cabins
   WHERE demo_dataset = 'recruiter-v1') AS marked_cabin_count,
  (SELECT count(*)
   FROM public.cabins
   WHERE demo_dataset IS DISTINCT FROM 'recruiter-v1')
    AS unmarked_cabin_count,
  (SELECT count(*)
   FROM public.guests
   WHERE demo_dataset = 'recruiter-v1') AS marked_guest_count,
  (SELECT count(*)
   FROM public.guests
   WHERE demo_dataset IS DISTINCT FROM 'recruiter-v1')
    AS unmarked_guest_count,
  (SELECT count(*)
   FROM public.bookings AS booking
   LEFT JOIN public.cabins AS cabin ON cabin.id = booking."cabinId"
   LEFT JOIN public.guests AS guest ON guest.id = booking."guestId"
   WHERE cabin.id IS NULL OR guest.id IS NULL) AS orphan_booking_count;

-- 8. Minimum non-secret Auth metadata. This intentionally returns no email,
-- user ID, password field, token, or raw metadata. It supports the Stage B
-- decision without making a credential artifact.
SELECT
  count(*) AS auth_user_count,
  count(*) FILTER (
    WHERE email_confirmed_at IS NOT NULL
      AND deleted_at IS NULL
      AND (banned_until IS NULL OR banned_until < now())
  ) AS usable_auth_user_count,
  count(*) FILTER (
    WHERE lower(coalesce(email, '')) ~ '(review|recruit)'
      OR lower(coalesce(
        raw_user_meta_data->>'fullName',
        raw_user_meta_data->>'full_name',
        raw_user_meta_data->>'name',
        ''
      )) ~ '(review|recruit)'
  ) AS reviewer_or_recruiter_label_match_count,
  count(*) FILTER (
    WHERE lower(coalesce(email, '')) ~ '(demo|test)'
      OR lower(coalesce(
        raw_user_meta_data->>'fullName',
        raw_user_meta_data->>'full_name',
        raw_user_meta_data->>'name',
        ''
      )) ~ '(demo|test)'
  ) AS demo_or_test_label_match_count,
  count(*) FILTER (
    WHERE last_sign_in_at IS NOT NULL
  ) AS previously_signed_in_user_count
FROM auth.users;
