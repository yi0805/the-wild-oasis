-- Task 032 read-only hosted verification after the permanent reset.
-- This file does not invoke the reset and does not mutate database or Storage data.

WITH function_metadata AS (
  SELECT function_row.*
  FROM pg_catalog.pg_proc AS function_row
  JOIN pg_catalog.pg_namespace AS function_schema
    ON function_schema.oid = function_row.pronamespace
  WHERE function_schema.nspname = 'private'
    AND function_row.proname = 'reset_recruiter_demo_data'
    AND function_row.pronargs = 0
), function_acl AS (
  SELECT privilege.grantee, privilege.privilege_type
  FROM function_metadata
  CROSS JOIN LATERAL aclexplode(
    COALESCE(
      function_metadata.proacl,
      acldefault('f', function_metadata.proowner)
    )
  ) AS privilege
), invalid_counts AS (
  SELECT
    (
      SELECT count(*)
      FROM public.bookings AS booking
      LEFT JOIN public.cabins AS cabin ON cabin.id = booking."cabinId"
      LEFT JOIN public.guests AS guest ON guest.id = booking."guestId"
      WHERE cabin.id IS NULL OR guest.id IS NULL
    ) AS orphan_bookings,
    (
      SELECT count(*)
      FROM public.bookings
      WHERE status NOT IN ('unconfirmed', 'checked-in', 'checked-out')
    ) AS unsupported_statuses,
    (
      SELECT count(*)
      FROM public.bookings
      WHERE "startDate" >= "endDate"
        OR "numNights" <>
          (("endDate" AT TIME ZONE 'UTC')::date - ("startDate" AT TIME ZONE 'UTC')::date)
        OR "numGuests" <= 0
    ) AS invalid_booking_shape,
    (
      SELECT count(*)
      FROM public.bookings AS booking
      JOIN public.cabins AS cabin ON cabin.id = booking."cabinId"
      WHERE booking."numGuests" > cabin."maxCapacity"
    ) AS over_capacity_bookings,
    (
      SELECT count(*)
      FROM public.bookings AS booking
      JOIN public.cabins AS cabin ON cabin.id = booking."cabinId"
      CROSS JOIN public.settings AS setting
      WHERE booking."cabinPrice" < 0
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
    ) AS invalid_price_rows,
    (
      SELECT count(*)
      FROM public.bookings AS first_booking
      JOIN public.bookings AS second_booking
        ON second_booking."cabinId" = first_booking."cabinId"
        AND second_booking.id > first_booking.id
        AND first_booking."startDate" < second_booking."endDate"
        AND second_booking."startDate" < first_booking."endDate"
    ) AS overlapping_booking_pairs,
    (
      SELECT count(*)
      FROM public.cabins
      WHERE demo_dataset IS DISTINCT FROM 'recruiter-v1'
    ) AS unmarked_cabins,
    (
      SELECT count(*)
      FROM public.guests
      WHERE demo_dataset IS DISTINCT FROM 'recruiter-v1'
    ) AS unmarked_guests,
    (
      SELECT count(*)
      FROM public.bookings
      WHERE demo_dataset IS DISTINCT FROM 'recruiter-v1'
    ) AS unmarked_bookings,
    (
      SELECT count(*)
      FROM public.guests
      WHERE email !~ '^[a-z.]+@example[.]test$'
        OR "nationalID" !~ '^DEMO-[0-9]{4}$'
    ) AS invalid_synthetic_guests,
    (
      SELECT count(*)
      FROM public.cabins
      WHERE name !~ '^00[1-8]$'
        OR image <>
          'https://qgbaudwrxhlxcqqraneb.supabase.co/storage/v1/object/public/cabin-images/cabin-'
          || name || '.jpg'
    ) AS invalid_canonical_cabins,
    (
      SELECT count(*)
      FROM public.cabin_image_cleanup_queue AS queue
      WHERE queue.object_name !~
          '^cabin-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|png|webp)$'
        OR queue.object_name IN (
          'cabin-001.jpg', 'cabin-002.jpg', 'cabin-003.jpg', 'cabin-004.jpg',
          'cabin-005.jpg', 'cabin-006.jpg', 'cabin-007.jpg', 'cabin-008.jpg'
        )
        OR EXISTS (
          SELECT 1
          FROM public.cabins AS cabin
          WHERE cabin.image =
            'https://qgbaudwrxhlxcqqraneb.supabase.co/storage/v1/object/public/cabin-images/'
            || queue.object_name
        )
    ) AS invalid_cleanup_entries
)
SELECT json_build_object(
  'counts', json_build_object(
    'cabins', (SELECT count(*) FROM public.cabins),
    'guests', (SELECT count(*) FROM public.guests),
    'bookings', (SELECT count(*) FROM public.bookings),
    'settings', (SELECT count(*) FROM public.settings),
    'cleanup_queue', (SELECT count(*) FROM public.cabin_image_cleanup_queue)
  ),
  'settings', (
    SELECT row_to_json(setting)
    FROM (
      SELECT id, "minBookingLength", "maxBookingLength", "maxGuestsPerBooking", "breakfastPrice"
      FROM public.settings
    ) AS setting
  ),
  'booking_distribution', (
    SELECT json_build_object(
      'checked_out', count(*) FILTER (WHERE status = 'checked-out'),
      'checked_in', count(*) FILTER (WHERE status = 'checked-in'),
      'unconfirmed', count(*) FILTER (WHERE status = 'unconfirmed'),
      'paid', count(*) FILTER (WHERE "isPaid"),
      'unpaid', count(*) FILTER (WHERE NOT "isPaid"),
      'breakfast', count(*) FILTER (WHERE "hasBreakfast"),
      'no_breakfast', count(*) FILTER (WHERE NOT "hasBreakfast"),
      'arrivals_today', count(*) FILTER (
        WHERE status = 'unconfirmed'
          AND ("startDate" AT TIME ZONE 'UTC')::date =
            (statement_timestamp() AT TIME ZONE 'UTC')::date
      ),
      'departures_today', count(*) FILTER (
        WHERE status = 'checked-in'
          AND ("endDate" AT TIME ZONE 'UTC')::date =
            (statement_timestamp() AT TIME ZONE 'UTC')::date
      )
    )
    FROM public.bookings
  ),
  'dashboard_windows', (
    SELECT json_build_object(
      'days_7', count(*) FILTER (
        WHERE created_at >=
          (((statement_timestamp() AT TIME ZONE 'UTC')::date - 7)::timestamp AT TIME ZONE 'UTC')
      ),
      'days_30', count(*) FILTER (
        WHERE created_at >=
          (((statement_timestamp() AT TIME ZONE 'UTC')::date - 30)::timestamp AT TIME ZONE 'UTC')
      ),
      'days_90', count(*) FILTER (
        WHERE created_at >=
          (((statement_timestamp() AT TIME ZONE 'UTC')::date - 90)::timestamp AT TIME ZONE 'UTC')
      )
    )
    FROM public.bookings
  ),
  'cabin_008_prices', (
    SELECT json_agg(json_build_object(
      'nights', booking."numNights",
      'cabin_price', booking."cabinPrice"
    ) ORDER BY booking."numNights")
    FROM public.bookings AS booking
    JOIN public.cabins AS cabin ON cabin.id = booking."cabinId"
    WHERE cabin.name = '008'
      AND booking."numNights" IN (30, 31)
  ),
  'invalid_counts', (SELECT row_to_json(invalid_counts) FROM invalid_counts),
  'cabin_image_objects', (
    SELECT json_build_object(
      'count', count(*),
      'names', array_agg(name ORDER BY name)
    )
    FROM storage.objects
    WHERE bucket_id = 'cabin-images'
  ),
  'auth_snapshot', (
    SELECT json_build_object(
      'count', count(*),
      'digest', md5(COALESCE(string_agg(id::text || COALESCE(raw_user_meta_data::text, ''), '|' ORDER BY id), ''))
    )
    FROM auth.users
  ),
  'avatar_snapshot', (
    SELECT json_build_object(
      'count', count(*),
      'digest', md5(COALESCE(string_agg(name, '|' ORDER BY name), ''))
    )
    FROM storage.objects
    WHERE bucket_id = 'avatars'
  ),
  'function_security', (
    SELECT json_build_object(
      'security_definer', prosecdef,
      'search_path', proconfig,
      'public_execute', EXISTS (
        SELECT 1 FROM function_acl
        WHERE grantee = 0 AND privilege_type = 'EXECUTE'
      ),
      'anon_schema_usage', has_schema_privilege('anon', 'private', 'USAGE'),
      'authenticated_schema_usage', has_schema_privilege('authenticated', 'private', 'USAGE'),
      'anon_execute', has_function_privilege('anon', 'private.reset_recruiter_demo_data()', 'EXECUTE'),
      'authenticated_execute', has_function_privilege('authenticated', 'private.reset_recruiter_demo_data()', 'EXECUTE')
    )
    FROM function_metadata
  )
) AS task_032_post_apply_verification;
