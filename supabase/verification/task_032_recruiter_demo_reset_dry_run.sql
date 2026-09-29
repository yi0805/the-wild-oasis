-- Task 032 hosted dry run. Run only after the migration and, for the current
-- hosted project, the numeric function repair have been manually applied and
-- reviewed. The reset and all data changes are rolled back.

-- Capture these baseline counts before opening the dry-run transaction. On the
-- freshly audited, migrated-but-not-reset environment, expect 8/32/24/1/0.
SELECT
  (SELECT count(*) FROM public.cabins) AS cabins_before,
  (SELECT count(*) FROM public.guests) AS guests_before,
  (SELECT count(*) FROM public.bookings) AS bookings_before,
  (SELECT count(*) FROM public.settings) AS settings_before,
  (SELECT count(*) FROM public.cabin_image_cleanup_queue) AS cleanup_queue_before;

-- Confirm that browser roles cannot discover/use the private schema or invoke
-- the reset, and that the function is not SECURITY DEFINER.
SELECT
  has_schema_privilege('anon', 'private', 'USAGE') AS anon_schema_usage,
  has_schema_privilege('authenticated', 'private', 'USAGE') AS authenticated_schema_usage,
  has_function_privilege(
    'anon',
    'private.reset_recruiter_demo_data()',
    'EXECUTE'
  ) AS anon_execute,
  has_function_privilege(
    'authenticated',
    'private.reset_recruiter_demo_data()',
    'EXECUTE'
  ) AS authenticated_execute,
  function_metadata.prosecdef AS security_definer
FROM pg_catalog.pg_proc AS function_metadata
JOIN pg_catalog.pg_namespace AS function_schema
  ON function_schema.oid = function_metadata.pronamespace
WHERE function_schema.nspname = 'private'
  AND function_metadata.proname = 'reset_recruiter_demo_data'
  AND function_metadata.pronargs = 0;

BEGIN;

SELECT private.reset_recruiter_demo_data();

-- The second call proves repeatability in the same transaction and must leave
-- the same canonical result.
SELECT private.reset_recruiter_demo_data();

SELECT
  (SELECT count(*) FROM public.cabins WHERE demo_dataset = 'recruiter-v1')
    AS recruiter_cabins,
  (SELECT count(*) FROM public.guests WHERE demo_dataset = 'recruiter-v1')
    AS recruiter_guests,
  (SELECT count(*) FROM public.bookings WHERE demo_dataset = 'recruiter-v1')
    AS recruiter_bookings,
  (SELECT count(*) FROM public.settings) AS settings_count,
  (SELECT count(*) FROM public.settings WHERE id = 1) AS settings_id_one_count;

SELECT
  count(*) FILTER (WHERE status = 'checked-out') AS checked_out,
  count(*) FILTER (WHERE status = 'checked-in') AS checked_in,
  count(*) FILTER (WHERE status = 'unconfirmed') AS unconfirmed,
  count(*) FILTER (WHERE "isPaid") AS paid,
  count(*) FILTER (WHERE NOT "isPaid") AS unpaid,
  count(*) FILTER (WHERE "hasBreakfast") AS with_breakfast,
  count(*) FILTER (WHERE NOT "hasBreakfast") AS without_breakfast,
  count(*) FILTER (
    WHERE status = 'unconfirmed'
      AND ("startDate" AT TIME ZONE 'UTC')::date =
        (statement_timestamp() AT TIME ZONE 'UTC')::date
  ) AS arrivals_today,
  count(*) FILTER (
    WHERE status = 'checked-in'
      AND ("endDate" AT TIME ZONE 'UTC')::date =
        (statement_timestamp() AT TIME ZONE 'UTC')::date
  ) AS departures_today
FROM public.bookings
WHERE demo_dataset = 'recruiter-v1';

SELECT
  count(*) FILTER (
    WHERE created_at >=
      (((statement_timestamp() AT TIME ZONE 'UTC')::date - 7)::timestamp AT TIME ZONE 'UTC')
  ) AS dashboard_7_day_bookings,
  count(*) FILTER (
    WHERE created_at >=
      (((statement_timestamp() AT TIME ZONE 'UTC')::date - 30)::timestamp AT TIME ZONE 'UTC')
  ) AS dashboard_30_day_bookings,
  count(*) FILTER (
    WHERE created_at >=
      (((statement_timestamp() AT TIME ZONE 'UTC')::date - 90)::timestamp AT TIME ZONE 'UTC')
  ) AS dashboard_90_day_bookings
FROM public.bookings
WHERE demo_dataset = 'recruiter-v1';

-- Regression for the original smallint overflow: Cabin 008 deliberately has
-- 30-night and 31-night bookings whose undiscounted cabin prices exceed 32767.
-- Numeric widening must produce 42000 and 43400 without overflow.
DO $cabin_008_price_regression$
BEGIN
  IF (
    SELECT count(*)
    FROM public.bookings AS booking
    JOIN public.cabins AS cabin ON cabin.id = booking."cabinId"
    WHERE booking.demo_dataset = 'recruiter-v1'
      AND cabin.name = '008'
      AND booking."numNights" IN (30, 31)
      AND booking."cabinPrice"::numeric =
        booking."numNights"::numeric
          * (cabin."regularPrice"::numeric - cabin.discount::numeric)
      AND booking."cabinPrice"::numeric =
        CASE booking."numNights"
          WHEN 30 THEN 42000::numeric
          WHEN 31 THEN 43400::numeric
        END
  ) <> 2
  THEN
    RAISE EXCEPTION
      'Cabin 008 widened-price regression failed for 30-night/31-night bookings';
  END IF;
END
$cabin_008_price_regression$;

-- Every invalid-count result below must be zero.
SELECT
  (
    SELECT count(*)
    FROM public.bookings AS booking
    LEFT JOIN public.cabins AS cabin ON cabin.id = booking."cabinId"
    LEFT JOIN public.guests AS guest ON guest.id = booking."guestId"
    WHERE booking.demo_dataset = 'recruiter-v1'
      AND (cabin.id IS NULL OR guest.id IS NULL)
  ) AS orphan_bookings,
  (
    SELECT count(*)
    FROM public.bookings
    WHERE demo_dataset = 'recruiter-v1'
      AND (
        status NOT IN ('unconfirmed', 'checked-in', 'checked-out')
        OR "startDate" >= "endDate"
        OR "numNights" <>
          (("endDate" AT TIME ZONE 'UTC')::date - ("startDate" AT TIME ZONE 'UTC')::date)
        OR "numGuests" <= 0
      )
  ) AS invalid_booking_shape,
  (
    SELECT count(*)
    FROM public.bookings AS booking
    JOIN public.cabins AS cabin ON cabin.id = booking."cabinId"
    WHERE booking.demo_dataset = 'recruiter-v1'
      AND booking."numGuests" > cabin."maxCapacity"
  ) AS over_capacity_bookings,
  (
    SELECT count(*)
    FROM public.bookings AS booking
    JOIN public.cabins AS cabin ON cabin.id = booking."cabinId"
    CROSS JOIN public.settings AS setting
    WHERE booking.demo_dataset = 'recruiter-v1'
      AND (
        booking."cabinPrice" < 0
        OR booking."extrasPrice" < 0
        OR booking."totalPrice" < 0
        OR cabin.discount < 0
        OR cabin.discount > cabin."regularPrice"
        OR booking."cabinPrice"::numeric <>
          booking."numNights"::numeric
            * (cabin."regularPrice"::numeric - cabin.discount::numeric)
        OR booking."extrasPrice"::numeric <>
          CASE
            WHEN booking."hasBreakfast"
            THEN booking."numNights"::numeric
              * booking."numGuests"::numeric
              * setting."breakfastPrice"::numeric
            ELSE 0::numeric
          END
        OR booking."totalPrice"::numeric <>
          booking."cabinPrice"::numeric + booking."extrasPrice"::numeric
      )
  ) AS invalid_price_rows,
  (
    SELECT count(*)
    FROM public.bookings AS first_booking
    JOIN public.bookings AS second_booking
      ON second_booking."cabinId" = first_booking."cabinId"
      AND second_booking.id > first_booking.id
      AND first_booking."startDate" < second_booking."endDate"
      AND second_booking."startDate" < first_booking."endDate"
    WHERE first_booking.demo_dataset = 'recruiter-v1'
      AND second_booking.demo_dataset = 'recruiter-v1'
  ) AS overlapping_booking_pairs;

SELECT
  count(*) FILTER (
    WHERE demo_dataset IS DISTINCT FROM 'recruiter-v1'
  ) AS non_recruiter_cabins,
  count(*) FILTER (
    WHERE image NOT LIKE
      'https://qgbaudwrxhlxcqqraneb.supabase.co/storage/v1/object/public/cabin-images/cabin-00_.jpg'
  ) AS invalid_canonical_images
FROM public.cabins;

SELECT
  (SELECT count(*) FROM public.guests WHERE demo_dataset IS DISTINCT FROM 'recruiter-v1')
    AS non_recruiter_guests,
  (SELECT count(*) FROM public.bookings WHERE demo_dataset IS DISTINCT FROM 'recruiter-v1')
    AS non_recruiter_bookings,
  (SELECT count(*) FROM public.guests WHERE email NOT LIKE '%@example.test')
    AS non_synthetic_guest_emails,
  (SELECT count(*) FROM public.guests WHERE "nationalID" !~ '^DEMO-[0-9]{4}$')
    AS invalid_demo_national_ids;

SELECT
  count(*) AS cleanup_queue_count,
  count(*) FILTER (
    WHERE object_name !~
      '^cabin-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|png|webp)$'
  ) AS invalid_cleanup_names,
  count(*) FILTER (
    WHERE object_name IN (
      'cabin-001.jpg', 'cabin-002.jpg', 'cabin-003.jpg', 'cabin-004.jpg',
      'cabin-005.jpg', 'cabin-006.jpg', 'cabin-007.jpg', 'cabin-008.jpg'
    )
  ) AS permanent_images_queued
FROM public.cabin_image_cleanup_queue;

SELECT
  id,
  "minBookingLength",
  "maxBookingLength",
  "maxGuestsPerBooking",
  "breakfastPrice"
FROM public.settings;

ROLLBACK;

-- These counts must match the first baseline query, proving that the dry run
-- did not persist the reset.
SELECT
  (SELECT count(*) FROM public.cabins) AS cabins_after_rollback,
  (SELECT count(*) FROM public.guests) AS guests_after_rollback,
  (SELECT count(*) FROM public.bookings) AS bookings_after_rollback,
  (SELECT count(*) FROM public.settings) AS settings_after_rollback,
  (SELECT count(*) FROM public.cabin_image_cleanup_queue) AS cleanup_queue_after_rollback;
