-- Task 032: canonical recruiter demo dataset and safe reset function.
--
-- MANUAL APPLY ONLY. Hosted Supabase migration history is not reconciled; do
-- not use `supabase db push`. Review and run this whole file once in Supabase
-- SQL Editor. The transaction fails closed if the confirmed legacy demo
-- baseline is no longer present.

BEGIN;

ALTER TABLE public.cabins
  ADD COLUMN demo_dataset text NULL;
ALTER TABLE public.guests
  ADD COLUMN demo_dataset text NULL;
ALTER TABLE public.bookings
  ADD COLUMN demo_dataset text NULL;

DO $legacy_designation$
DECLARE
  legacy_cabin_count integer;
  legacy_guest_count integer;
  legacy_booking_count integer;
  legacy_fixture_guest_count integer;
  legacy_linked_guest_count integer;
  legacy_unmatched_guest_ids bigint[];
BEGIN
  SELECT count(*) INTO legacy_cabin_count FROM public.cabins;
  SELECT count(*) INTO legacy_guest_count FROM public.guests;
  SELECT count(*) INTO legacy_booking_count FROM public.bookings;

  IF legacy_cabin_count <> 8
    OR legacy_guest_count <> 32
    OR legacy_booking_count <> 24
  THEN
    RAISE EXCEPTION
      'Legacy demo designation refused: expected 8 cabins, 32 guests, and 24 bookings; found %, %, and %',
      legacy_cabin_count,
      legacy_guest_count,
      legacy_booking_count;
  END IF;

  -- Verify the exact 30-row historical tutorial fixture without retaining its
  -- legacy identities in this canonical migration. Each digest covers name,
  -- email, national ID (including null), nationality, and flag URL.
  SELECT count(*)
  INTO legacy_fixture_guest_count
  FROM public.guests AS guest
  JOIN (
    VALUES
      ('036054dda88e415fe4a304a4efee60fa'),
      ('0d61cd326a22dd2113511e3eea646307'),
      ('20f5717f7649a912588804a8583d5357'),
      ('2166bba0aaf9b27401d46de6168b4af5'),
      ('262671586b04a9f13c4ce3b8e8a086f4'),
      ('2788202463672897fdb4483a766a7777'),
      ('299e05bfea2fc37c23ce733c27ddf52a'),
      ('2a44c18472eaa002fbed69ed93230131'),
      ('3af6ab94d70bdbdfd04e06217b6a7bae'),
      ('49bb67c7ebaf785091a0c31101e8c3ac'),
      ('557457290983221493cc2e0e7288a291'),
      ('6237920f07e5e9f8aca084367d1556bd'),
      ('6e4b85ef36a662b37357b04fc558bd45'),
      ('787d07dedff74456c1083aedb59e0af7'),
      ('7b7a7a9e6a5c3a3228f7df0aad060c0d'),
      ('7e939104a21487dd8d4ee0145a342687'),
      ('854c01399cd20351e16a9ef7033b9d90'),
      ('94bd48cf3c8ee0af1c83b4e2dcac2652'),
      ('94c1e985efbf11ced1a88f354b16657a'),
      ('a765ff15f2c30644f82bad75c28b484e'),
      ('aa546109da35d2720916938bc559db56'),
      ('b05cfda411592196a14a55c3ac4a3c1d'),
      ('b752359560fd0051985eb68daf7351da'),
      ('c2cf6e0918103598efa1878d8d22185a'),
      ('d1b67e1c18f25aa3b12a130af8813b91'),
      ('de15ad4a1a892b5ce9537b31c5d13790'),
      ('e4637c814b364c3f50b0176de03d2d49'),
      ('eb876a914a2bfecbda47e7aa741d4587'),
      ('eed16b85ef7f0984d285181073de3249'),
      ('f44af100ad217076dbc27d49ecda8cc4')
  ) AS expected(identity_md5)
    ON md5(concat_ws(
      chr(31),
      coalesce(guest."fullName", '<NULL>'),
      coalesce(guest.email, '<NULL>'),
      coalesce(guest."nationalID", '<NULL>'),
      coalesce(guest.nationality, '<NULL>'),
      coalesce(guest."countryFlag", '<NULL>')
    )) = expected.identity_md5;

  IF legacy_fixture_guest_count <> 30 THEN
    RAISE EXCEPTION
      'Legacy demo designation refused: expected all 30 historical tutorial guest identities; matched %',
      legacy_fixture_guest_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.guests AS guest
    WHERE guest.id = 95
      AND md5(concat_ws(
        chr(31),
        coalesce(guest."fullName", '<NULL>'),
        coalesce(guest.email, '<NULL>'),
        coalesce(guest."nationalID", '<NULL>'),
        coalesce(guest.nationality, '<NULL>'),
        coalesce(guest."countryFlag", '<NULL>')
      )) = '62638bd4fe18c46a26febc9980dcb99e'
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.guests AS guest
    WHERE guest.id = 96
      AND md5(concat_ws(
        chr(31),
        coalesce(guest."fullName", '<NULL>'),
        coalesce(guest.email, '<NULL>'),
        coalesce(guest."nationalID", '<NULL>'),
        coalesce(guest.nationality, '<NULL>'),
        coalesce(guest."countryFlag", '<NULL>')
      )) = '982351c7b9ee746e25323ea683ab6de6'
  )
  THEN
    RAISE EXCEPTION
      'Legacy demo designation refused: confirmed test guests 95 and 96 do not match the audited identities';
  END IF;

  SELECT count(DISTINCT booking."guestId")
  INTO legacy_linked_guest_count
  FROM public.bookings AS booking;

  SELECT array_agg(guest.id ORDER BY guest.id)
  INTO legacy_unmatched_guest_ids
  FROM public.guests AS guest
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.bookings AS booking
    WHERE booking."guestId" = guest.id
  );

  IF legacy_linked_guest_count <> 20
    OR legacy_unmatched_guest_ids IS DISTINCT FROM
      ARRAY[66, 67, 69, 70, 88, 89, 90, 91, 92, 93, 94, 96]::bigint[]
  THEN
    RAISE EXCEPTION
      'Legacy demo designation refused: expected 20 booking-linked guests and audited unmatched guest IDs; found % and %',
      legacy_linked_guest_count,
      legacy_unmatched_guest_ids;
  END IF;

  IF (SELECT count(*) FROM public.settings) <> 1
    OR NOT EXISTS (
      SELECT 1
      FROM public.settings
      WHERE id = 1
        AND "minBookingLength" = 3
        AND "maxBookingLength" = 90
        AND "maxGuestsPerBooking" = 8
        AND "breakfastPrice" = 15
    )
  THEN
    RAISE EXCEPTION
      'Legacy demo designation refused: settings must contain only id 1 with values 3/90/8/15';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (
      VALUES
        ('001', 2, 200, 0, 'cabin-001.jpg', '45c592ea0ef928d5cd02e0b433c8ae56'),
        ('002', 2, 350, 25, 'cabin-002.jpg', 'd6c000a0cae925d97a457e3b75c12675'),
        ('003', 4, 300, 0, 'cabin-003.jpg', 'afe7d1bea8616f5b461c66a2cdfe4ffb'),
        ('004', 4, 500, 50, 'cabin-004.jpg', 'a43171012603cf7d4f0fb8499877438b'),
        ('005', 6, 350, 0, 'cabin-005.jpg', 'd55d7b511fe1b28560b448969f4ebf5e'),
        ('006', 6, 800, 100, 'cabin-006.jpg', '6ac44400e7acee91de84591087af5bb1'),
        ('007', 8, 600, 100, 'cabin-007.jpg', 'b23385d3c779dadc63b297ed2405d9cd'),
        ('008', 10, 1400, 0, 'cabin-008.jpg', '1ad1a84db2db8ec2b3378acb33ebf7cd')
    ) AS expected(
      name,
      max_capacity,
      regular_price,
      discount,
      object_name,
      description_md5
    )
    LEFT JOIN public.cabins AS cabin
      ON cabin.name = expected.name
      AND cabin."maxCapacity" = expected.max_capacity
      AND cabin."regularPrice" = expected.regular_price
      AND cabin.discount = expected.discount
      AND md5(cabin.description) = expected.description_md5
      AND cabin.image =
        'https://qgbaudwrxhlxcqqraneb.supabase.co/storage/v1/object/public/cabin-images/'
        || expected.object_name
    WHERE cabin.id IS NULL
  )
  THEN
    RAISE EXCEPTION
      'Legacy demo designation refused: canonical cabin identity, capacity, pricing, or image URL differs from the confirmed baseline';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.bookings AS booking
    LEFT JOIN public.cabins AS cabin ON cabin.id = booking."cabinId"
    LEFT JOIN public.guests AS guest ON guest.id = booking."guestId"
    WHERE cabin.id IS NULL OR guest.id IS NULL
  )
  THEN
    RAISE EXCEPTION
      'Legacy demo designation refused: an existing booking has an orphan cabin or guest reference';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.cabins WHERE demo_dataset IS NOT NULL
    UNION ALL
    SELECT 1 FROM public.guests WHERE demo_dataset IS NOT NULL
    UNION ALL
    SELECT 1 FROM public.bookings WHERE demo_dataset IS NOT NULL
  )
  THEN
    RAISE EXCEPTION
      'Legacy demo designation refused: demo_dataset is already populated';
  END IF;

  UPDATE public.bookings
  SET demo_dataset = 'recruiter-v1';

  UPDATE public.guests
  SET demo_dataset = 'recruiter-v1';

  UPDATE public.cabins
  SET demo_dataset = 'recruiter-v1';
END
$legacy_designation$;

-- New cabins created or duplicated through the reviewer UI belong to this
-- permanently designated disposable demo environment and are removed by the
-- next reset. Guests and bookings have no browser insert path and keep a null
-- default so their scope remains explicit.
ALTER TABLE public.cabins
  ALTER COLUMN demo_dataset SET DEFAULT 'recruiter-v1';

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC;
REVOKE ALL ON SCHEMA private FROM anon;
REVOKE ALL ON SCHEMA private FROM authenticated;

CREATE OR REPLACE FUNCTION private.reset_recruiter_demo_data()
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $reset_function$
DECLARE
  dataset_marker constant text := 'recruiter-v1';
  image_base_url constant text :=
    'https://qgbaudwrxhlxcqqraneb.supabase.co/storage/v1/object/public/cabin-images/';
  owned_object_pattern constant text :=
    '^cabin-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|png|webp)$';
  utc_today date;
  utc_anchor timestamptz;
  settings_count integer;
  settings_id_one_count integer;
  removed_owned_objects text[];
BEGIN
  -- A fixed two-key transaction advisory lock prevents concurrent resets.
  PERFORM pg_catalog.pg_advisory_xact_lock(20260928, 32);

  utc_today := (statement_timestamp() AT TIME ZONE 'UTC')::date;
  utc_anchor := utc_today::timestamp AT TIME ZONE 'UTC';

  SELECT count(*), count(*) FILTER (WHERE id = 1)
  INTO settings_count, settings_id_one_count
  FROM public.settings;

  IF settings_count <> 1 OR settings_id_one_count <> 1 THEN
    RAISE EXCEPTION
      'Recruiter demo reset refused: settings must contain exactly one row with id 1';
  END IF;

  IF to_regclass('public.cabin_image_cleanup_queue') IS NULL THEN
    RAISE EXCEPTION
      'Recruiter demo reset refused: cabin_image_cleanup_queue is missing';
  END IF;

  -- Fail before deleting anything if an unmarked booking would retain a
  -- foreign-key reference to a marked cabin or guest.
  IF EXISTS (
    SELECT 1
    FROM public.bookings AS booking
    LEFT JOIN public.cabins AS cabin ON cabin.id = booking."cabinId"
    LEFT JOIN public.guests AS guest ON guest.id = booking."guestId"
    WHERE booking.demo_dataset IS DISTINCT FROM dataset_marker
      AND (
        cabin.demo_dataset = dataset_marker
        OR guest.demo_dataset = dataset_marker
      )
  )
  THEN
    RAISE EXCEPTION
      'Recruiter demo reset refused: an unmarked booking references marked demo data';
  END IF;

  -- Preserve non-demo rows. Refuse canonical identity collisions instead of
  -- deleting by mutable names, emails, image URLs, or relationships.
  IF EXISTS (
    SELECT 1
    FROM public.cabins
    WHERE demo_dataset IS DISTINCT FROM dataset_marker
      AND (
        name IN ('001', '002', '003', '004', '005', '006', '007', '008')
        OR image IN (
          image_base_url || 'cabin-001.jpg',
          image_base_url || 'cabin-002.jpg',
          image_base_url || 'cabin-003.jpg',
          image_base_url || 'cabin-004.jpg',
          image_base_url || 'cabin-005.jpg',
          image_base_url || 'cabin-006.jpg',
          image_base_url || 'cabin-007.jpg',
          image_base_url || 'cabin-008.jpg'
        )
      )
  )
  THEN
    RAISE EXCEPTION
      'Recruiter demo reset refused: an unmarked cabin conflicts with a canonical identity';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.guests
    WHERE demo_dataset IS DISTINCT FROM dataset_marker
      AND (
        "nationalID" ~ '^DEMO-(000[1-9]|001[0-9]|002[0-4])$'
        OR email IN (
          'alex.rowan@example.test',
          'jamie.chen@example.test',
          'morgan.lee@example.test',
          'riley.okafor@example.test',
          'casey.novak@example.test',
          'taylor.singh@example.test',
          'jordan.alvarez@example.test',
          'avery.kim@example.test',
          'quinn.dubois@example.test',
          'samira.haddad@example.test',
          'devon.mensah@example.test',
          'skyler.ito@example.test',
          'cameron.silva@example.test',
          'reese.muller@example.test',
          'parker.nguyen@example.test',
          'drew.kowalski@example.test',
          'sage.petrov@example.test',
          'emery.wilson@example.test',
          'rowan.bennett@example.test',
          'finley.santos@example.test',
          'ari.cohen@example.test',
          'noel.anders@example.test',
          'remy.tan@example.test',
          'blair.campbell@example.test'
        )
      )
  )
  THEN
    RAISE EXCEPTION
      'Recruiter demo reset refused: an unmarked guest conflicts with a canonical identity';
  END IF;

  -- Record only strict app-owned UUID image names from demo cabins that are
  -- about to disappear. Fixed cabin-001.jpg ... cabin-008.jpg assets cannot
  -- match this pattern and can never enter the queue.
  SELECT COALESCE(
    array_agg(DISTINCT replace(cabin.image, image_base_url, '')),
    ARRAY[]::text[]
  )
  INTO removed_owned_objects
  FROM public.cabins AS cabin
  WHERE cabin.demo_dataset = dataset_marker
    AND cabin.image LIKE image_base_url || '%'
    AND replace(cabin.image, image_base_url, '') ~ owned_object_pattern
    AND cabin.image = image_base_url || replace(cabin.image, image_base_url, '');

  DELETE FROM public.bookings
  WHERE demo_dataset = dataset_marker;

  DELETE FROM public.guests
  WHERE demo_dataset = dataset_marker;

  DELETE FROM public.cabins
  WHERE demo_dataset = dataset_marker;

  INSERT INTO public.cabins (
    created_at,
    name,
    "maxCapacity",
    "regularPrice",
    discount,
    image,
    description,
    demo_dataset
  )
  VALUES
    (
      utc_anchor - interval '365 days',
      '001', 2, 200, 0, image_base_url || 'cabin-001.jpg',
      'Discover the ultimate luxury getaway for couples in the cozy wooden cabin 001. Nestled in a picturesque forest, this stunning cabin offers a secluded and intimate retreat. Inside, enjoy modern high-quality wood interiors, a comfortable seating area, a fireplace and a fully-equipped kitchen. The plush king-size bed, dressed in fine linens guarantees a peaceful nights sleep. Relax in the spa-like shower and unwind on the private deck with hot tub.',
      dataset_marker
    ),
    (
      utc_anchor - interval '365 days',
      '002', 2, 350, 25, image_base_url || 'cabin-002.jpg',
      'Escape to the serenity of nature and indulge in luxury in our cozy cabin 002. Perfect for couples, this cabin offers a secluded and intimate retreat in the heart of a picturesque forest. Inside, you will find warm and inviting interiors crafted from high-quality wood, a comfortable living area, a fireplace and a fully-equipped kitchen. The luxurious bedroom features a plush king-size bed and spa-like shower. Relax on the private deck with hot tub and take in the beauty of nature.',
      dataset_marker
    ),
    (
      utc_anchor - interval '365 days',
      '003', 4, 300, 0, image_base_url || 'cabin-003.jpg',
      'Experience luxury family living in our medium-sized wooden cabin 003. Perfect for families of up to 4 people, this cabin offers a comfortable and inviting space with all modern amenities. Inside, you will find warm and inviting interiors crafted from high-quality wood, a comfortable living area, a fireplace, and a fully-equipped kitchen. The bedrooms feature plush beds and spa-like bathrooms. The cabin has a private deck with a hot tub and outdoor seating area, perfect for taking in the natural surroundings.',
      dataset_marker
    ),
    (
      utc_anchor - interval '365 days',
      '004', 4, 500, 50, image_base_url || 'cabin-004.jpg',
      'Indulge in the ultimate luxury family vacation in this medium-sized cabin 004. Designed for families of up to 4, this cabin offers a sumptuous retreat for the discerning traveler. Inside, the cabin boasts of opulent interiors crafted from the finest quality wood, a comfortable living area, a fireplace, and a fully-equipped gourmet kitchen. The bedrooms are adorned with plush beds and spa-inspired en-suite bathrooms. Step outside to your private deck and soak in the natural surroundings while relaxing in your own hot tub.',
      dataset_marker
    ),
    (
      utc_anchor - interval '365 days',
      '005', 6, 350, 0, image_base_url || 'cabin-005.jpg',
      'Enjoy a comfortable and cozy getaway with your group or family in our spacious cabin 005. Designed to accommodate up to 6 people, this cabin offers a secluded retreat in the heart of nature. Inside, the cabin features warm and inviting interiors crafted from quality wood, a living area with fireplace, and a fully-equipped kitchen. The bedrooms are comfortable and equipped with en-suite bathrooms. Step outside to your private deck and take in the natural surroundings while relaxing in your own hot tub.',
      dataset_marker
    ),
    (
      utc_anchor - interval '365 days',
      '006', 6, 800, 100, image_base_url || 'cabin-006.jpg',
      'Experience the epitome of luxury with your group or family in our spacious wooden cabin 006. Designed to comfortably accommodate up to 6 people, this cabin offers a lavish retreat in the heart of nature. Inside, the cabin features opulent interiors crafted from premium wood, a grand living area with fireplace, and a fully-equipped gourmet kitchen. The bedrooms are adorned with plush beds and spa-like en-suite bathrooms. Step outside to your private deck and soak in the natural surroundings while relaxing in your own hot tub.',
      dataset_marker
    ),
    (
      utc_anchor - interval '365 days',
      '007', 8, 600, 100, image_base_url || 'cabin-007.jpg',
      'Accommodate your large group or multiple families in the spacious and grand wooden cabin 007. Designed to comfortably fit up to 8 people, this cabin offers a secluded retreat in the heart of beautiful forests and mountains. Inside, the cabin features warm and inviting interiors crafted from quality wood, multiple living areas with fireplace, and a fully-equipped kitchen. The bedrooms are comfortable and equipped with en-suite bathrooms. The cabin has a private deck with a hot tub and outdoor seating area, perfect for taking in the natural surroundings.',
      dataset_marker
    ),
    (
      utc_anchor - interval '365 days',
      '008', 10, 1400, 0, image_base_url || 'cabin-008.jpg',
      'Experience the epitome of luxury and grandeur with your large group or multiple families in our grand cabin 008. This cabin offers a lavish retreat that caters to all your needs and desires. The cabin features an opulent design and boasts of high-end finishes, intricate details and the finest quality wood throughout. Inside, the cabin features multiple grand living areas with fireplaces, a formal dining area, and a gourmet kitchen that is a chef''s dream. The bedrooms are designed for ultimate comfort and luxury, with plush beds and en-suite spa-inspired bathrooms. Step outside and immerse yourself in the beauty of nature from your private deck, featuring a luxurious hot tub and ample seating areas for ultimate relaxation and enjoyment.',
      dataset_marker
    );

  INSERT INTO public.guests (
    created_at,
    "fullName",
    email,
    nationality,
    "nationalID",
    "countryFlag",
    demo_dataset
  )
  VALUES
    (utc_anchor - interval '180 days', 'Alex Rowan', 'alex.rowan@example.test', 'New Zealand', 'DEMO-0001', 'https://flagcdn.com/nz.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Jamie Chen', 'jamie.chen@example.test', 'Singapore', 'DEMO-0002', 'https://flagcdn.com/sg.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Morgan Lee', 'morgan.lee@example.test', 'Canada', 'DEMO-0003', 'https://flagcdn.com/ca.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Riley Okafor', 'riley.okafor@example.test', 'Nigeria', 'DEMO-0004', 'https://flagcdn.com/ng.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Casey Novak', 'casey.novak@example.test', 'Czechia', 'DEMO-0005', 'https://flagcdn.com/cz.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Taylor Singh', 'taylor.singh@example.test', 'India', 'DEMO-0006', 'https://flagcdn.com/in.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Jordan Alvarez', 'jordan.alvarez@example.test', 'Mexico', 'DEMO-0007', 'https://flagcdn.com/mx.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Avery Kim', 'avery.kim@example.test', 'South Korea', 'DEMO-0008', 'https://flagcdn.com/kr.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Quinn Dubois', 'quinn.dubois@example.test', 'France', 'DEMO-0009', 'https://flagcdn.com/fr.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Samira Haddad', 'samira.haddad@example.test', 'Jordan', 'DEMO-0010', 'https://flagcdn.com/jo.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Devon Mensah', 'devon.mensah@example.test', 'Ghana', 'DEMO-0011', 'https://flagcdn.com/gh.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Skyler Ito', 'skyler.ito@example.test', 'Japan', 'DEMO-0012', 'https://flagcdn.com/jp.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Cameron Silva', 'cameron.silva@example.test', 'Brazil', 'DEMO-0013', 'https://flagcdn.com/br.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Reese Muller', 'reese.muller@example.test', 'Germany', 'DEMO-0014', 'https://flagcdn.com/de.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Parker Nguyen', 'parker.nguyen@example.test', 'Vietnam', 'DEMO-0015', 'https://flagcdn.com/vn.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Drew Kowalski', 'drew.kowalski@example.test', 'Poland', 'DEMO-0016', 'https://flagcdn.com/pl.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Sage Petrov', 'sage.petrov@example.test', 'Bulgaria', 'DEMO-0017', 'https://flagcdn.com/bg.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Emery Wilson', 'emery.wilson@example.test', 'Australia', 'DEMO-0018', 'https://flagcdn.com/au.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Rowan Bennett', 'rowan.bennett@example.test', 'Ireland', 'DEMO-0019', 'https://flagcdn.com/ie.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Finley Santos', 'finley.santos@example.test', 'Philippines', 'DEMO-0020', 'https://flagcdn.com/ph.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Ari Cohen', 'ari.cohen@example.test', 'Israel', 'DEMO-0021', 'https://flagcdn.com/il.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Noel Anders', 'noel.anders@example.test', 'Sweden', 'DEMO-0022', 'https://flagcdn.com/se.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Remy Tan', 'remy.tan@example.test', 'Malaysia', 'DEMO-0023', 'https://flagcdn.com/my.svg', dataset_marker),
    (utc_anchor - interval '180 days', 'Blair Campbell', 'blair.campbell@example.test', 'United Kingdom', 'DEMO-0024', 'https://flagcdn.com/gb.svg', dataset_marker);

  WITH booking_seed (
    cabin_name,
    national_id,
    created_day,
    start_day,
    end_day,
    status,
    has_breakfast,
    is_paid,
    num_guests,
    observations
  ) AS (
    VALUES
      ('001', 'DEMO-0001', -60, -45, -40, 'checked-out', false, true, 2, ''),
      ('001', 'DEMO-0002', -12, -4, 0, 'checked-in', true, true, 2, 'Please provide a quiet cabin setup.'),
      ('001', 'DEMO-0003', -2, 10, 17, 'unconfirmed', false, false, 1, ''),
      ('002', 'DEMO-0004', -35, -25, -22, 'checked-out', true, true, 2, ''),
      ('002', 'DEMO-0005', -8, -2, 3, 'checked-in', false, true, 2, 'Arriving after 20:00.'),
      ('002', 'DEMO-0006', -1, 15, 19, 'unconfirmed', true, false, 1, ''),
      ('003', 'DEMO-0007', -82, -70, -56, 'checked-out', false, true, 4, ''),
      ('003', 'DEMO-0008', -5, 0, 3, 'unconfirmed', true, false, 3, 'One guest requires a dairy-free breakfast.'),
      ('003', 'DEMO-0009', -20, 25, 34, 'unconfirmed', false, true, 2, ''),
      ('004', 'DEMO-0010', -25, -14, -7, 'checked-out', true, true, 4, ''),
      ('004', 'DEMO-0011', -10, -3, 4, 'checked-in', false, true, 2, ''),
      ('004', 'DEMO-0012', 0, 12, 15, 'unconfirmed', true, false, 3, 'Celebrating a graduation.'),
      ('005', 'DEMO-0013', -50, -35, -15, 'checked-out', false, true, 6, ''),
      ('005', 'DEMO-0014', -18, -10, 0, 'checked-in', true, true, 5, ''),
      ('005', 'DEMO-0015', -3, 14, 21, 'unconfirmed', true, false, 2, ''),
      ('006', 'DEMO-0016', -100, -90, -60, 'checked-out', true, true, 6, ''),
      ('006', 'DEMO-0017', -4, -1, 6, 'checked-in', false, true, 4, 'Late check-in requested.'),
      ('006', 'DEMO-0018', -12, 20, 35, 'unconfirmed', true, false, 5, ''),
      ('007', 'DEMO-0019', -22, -12, -9, 'checked-out', false, true, 8, ''),
      ('007', 'DEMO-0020', -7, 0, 8, 'unconfirmed', true, false, 6, 'Please prepare two adjacent sleeping areas.'),
      ('007', 'DEMO-0021', -2, 18, 28, 'unconfirmed', false, true, 3, ''),
      ('008', 'DEMO-0022', -65, -50, -20, 'checked-out', true, true, 8, ''),
      ('008', 'DEMO-0023', -9, -5, 5, 'checked-in', true, true, 7, 'Anniversary stay.'),
      ('008', 'DEMO-0024', -1, 14, 45, 'unconfirmed', false, false, 8, '')
  )
  INSERT INTO public.bookings (
    created_at,
    "startDate",
    "endDate",
    "numNights",
    "numGuests",
    "cabinPrice",
    "extrasPrice",
    "totalPrice",
    status,
    "hasBreakfast",
    "isPaid",
    observations,
    "cabinId",
    "guestId",
    demo_dataset
  )
  SELECT
    ((utc_today + seed.created_day)::timestamp + interval '12 hours') AT TIME ZONE 'UTC',
    (utc_today + seed.start_day)::timestamp AT TIME ZONE 'UTC',
    (utc_today + seed.end_day)::timestamp AT TIME ZONE 'UTC',
    seed.end_day - seed.start_day,
    seed.num_guests,
    (seed.end_day - seed.start_day)::numeric
      * (cabin."regularPrice"::numeric - cabin.discount::numeric),
    CASE
      WHEN seed.has_breakfast
      THEN (seed.end_day - seed.start_day)::numeric
        * seed.num_guests::numeric
        * 15::numeric
      ELSE 0::numeric
    END,
    (seed.end_day - seed.start_day)::numeric
      * (cabin."regularPrice"::numeric - cabin.discount::numeric)
      + CASE
          WHEN seed.has_breakfast
          THEN (seed.end_day - seed.start_day)::numeric
            * seed.num_guests::numeric
            * 15::numeric
          ELSE 0::numeric
        END,
    seed.status,
    seed.has_breakfast,
    seed.is_paid,
    seed.observations,
    cabin.id,
    guest.id,
    dataset_marker
  FROM booking_seed AS seed
  JOIN public.cabins AS cabin
    ON cabin.name = seed.cabin_name
    AND cabin.demo_dataset = dataset_marker
  JOIN public.guests AS guest
    ON guest."nationalID" = seed.national_id
    AND guest.demo_dataset = dataset_marker;

  UPDATE public.settings
  SET
    "minBookingLength" = 3,
    "maxBookingLength" = 90,
    "maxGuestsPerBooking" = 8,
    "breakfastPrice" = 15
  WHERE id = 1;

  INSERT INTO public.cabin_image_cleanup_queue (object_name)
  SELECT removed.object_name
  FROM unnest(removed_owned_objects) AS removed(object_name)
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.cabins AS cabin
    WHERE cabin.image = image_base_url || removed.object_name
  )
  ON CONFLICT (object_name) DO NOTHING;

  IF (SELECT count(*) FROM public.cabins WHERE demo_dataset = dataset_marker) <> 8
    OR (SELECT count(*) FROM public.guests WHERE demo_dataset = dataset_marker) <> 24
    OR (SELECT count(*) FROM public.bookings WHERE demo_dataset = dataset_marker) <> 24
  THEN
    RAISE EXCEPTION
      'Recruiter demo reset validation failed: canonical row counts are not 8/24/24';
  END IF;

  IF (SELECT count(*) FROM public.settings) <> 1
    OR NOT EXISTS (
      SELECT 1
      FROM public.settings
      WHERE id = 1
        AND "minBookingLength" = 3
        AND "maxBookingLength" = 90
        AND "maxGuestsPerBooking" = 8
        AND "breakfastPrice" = 15
    )
  THEN
    RAISE EXCEPTION
      'Recruiter demo reset validation failed: settings are not the canonical id 1 row';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.cabins
    WHERE demo_dataset = dataset_marker
      AND (
        name IS NULL
        OR "maxCapacity" IS NULL
        OR "regularPrice" IS NULL
        OR discount IS NULL
        OR image IS NULL
        OR description IS NULL
      )
  ) OR EXISTS (
    SELECT 1
    FROM public.guests
    WHERE demo_dataset = dataset_marker
      AND (
        "fullName" IS NULL
        OR email IS NULL
        OR nationality IS NULL
        OR "nationalID" IS NULL
        OR "countryFlag" IS NULL
      )
  ) OR EXISTS (
    SELECT 1
    FROM public.bookings
    WHERE demo_dataset = dataset_marker
      AND (
        "startDate" IS NULL
        OR "endDate" IS NULL
        OR "numNights" IS NULL
        OR "numGuests" IS NULL
        OR "cabinPrice" IS NULL
        OR "extrasPrice" IS NULL
        OR "totalPrice" IS NULL
        OR status IS NULL
        OR "hasBreakfast" IS NULL
        OR "isPaid" IS NULL
        OR observations IS NULL
        OR "cabinId" IS NULL
        OR "guestId" IS NULL
      )
  )
  THEN
    RAISE EXCEPTION
      'Recruiter demo reset validation failed: an active UI field is null';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.bookings AS booking
    LEFT JOIN public.cabins AS cabin ON cabin.id = booking."cabinId"
    LEFT JOIN public.guests AS guest ON guest.id = booking."guestId"
    WHERE booking.demo_dataset = dataset_marker
      AND (
        cabin.id IS NULL
        OR guest.id IS NULL
        OR cabin.demo_dataset IS DISTINCT FROM dataset_marker
        OR guest.demo_dataset IS DISTINCT FROM dataset_marker
      )
  )
  THEN
    RAISE EXCEPTION
      'Recruiter demo reset validation failed: orphan booking foreign key';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.bookings
    WHERE demo_dataset = dataset_marker
      AND status NOT IN ('unconfirmed', 'checked-in', 'checked-out')
  )
  THEN
    RAISE EXCEPTION
      'Recruiter demo reset validation failed: unsupported booking status';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.bookings
    WHERE demo_dataset = dataset_marker
      AND (
        "startDate" >= "endDate"
        OR "numNights" < 1
        OR "numNights" <>
          (("endDate" AT TIME ZONE 'UTC')::date - ("startDate" AT TIME ZONE 'UTC')::date)
        OR "numGuests" <= 0
      )
  )
  THEN
    RAISE EXCEPTION
      'Recruiter demo reset validation failed: invalid dates, nights, or guest count';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.bookings AS booking
    JOIN public.cabins AS cabin ON cabin.id = booking."cabinId"
    WHERE booking.demo_dataset = dataset_marker
      AND booking."numGuests" > cabin."maxCapacity"
  )
  THEN
    RAISE EXCEPTION
      'Recruiter demo reset validation failed: booking exceeds cabin capacity';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.cabins
    WHERE demo_dataset = dataset_marker
      AND (
        "regularPrice" < 0
        OR discount < 0
        OR discount > "regularPrice"
      )
  ) OR EXISTS (
    SELECT 1
    FROM public.bookings
    WHERE demo_dataset = dataset_marker
      AND ("cabinPrice" < 0 OR "extrasPrice" < 0 OR "totalPrice" < 0)
  )
  THEN
    RAISE EXCEPTION
      'Recruiter demo reset validation failed: invalid nonnegative price or discount';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.bookings AS booking
    JOIN public.cabins AS cabin ON cabin.id = booking."cabinId"
    CROSS JOIN public.settings AS setting
    WHERE booking.demo_dataset = dataset_marker
      AND (
        booking."cabinPrice"::numeric <>
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
  )
  THEN
    RAISE EXCEPTION
      'Recruiter demo reset validation failed: booking price arithmetic is inconsistent';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.bookings AS first_booking
    JOIN public.bookings AS second_booking
      ON second_booking."cabinId" = first_booking."cabinId"
      AND second_booking.id > first_booking.id
      AND first_booking."startDate" < second_booking."endDate"
      AND second_booking."startDate" < first_booking."endDate"
    WHERE first_booking.demo_dataset = dataset_marker
      AND second_booking.demo_dataset = dataset_marker
  )
  THEN
    RAISE EXCEPTION
      'Recruiter demo reset validation failed: canonical cabin bookings overlap';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.cabins AS cabin
    LEFT JOIN public.bookings AS booking
      ON booking."cabinId" = cabin.id
      AND booking.demo_dataset = dataset_marker
    WHERE cabin.demo_dataset = dataset_marker
    GROUP BY cabin.id
    HAVING count(booking.id) <> 3
  )
  THEN
    RAISE EXCEPTION
      'Recruiter demo reset validation failed: each canonical cabin must have three bookings';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (
      VALUES
        ('001', 2, 200, 0, 'cabin-001.jpg', '45c592ea0ef928d5cd02e0b433c8ae56'),
        ('002', 2, 350, 25, 'cabin-002.jpg', 'd6c000a0cae925d97a457e3b75c12675'),
        ('003', 4, 300, 0, 'cabin-003.jpg', 'afe7d1bea8616f5b461c66a2cdfe4ffb'),
        ('004', 4, 500, 50, 'cabin-004.jpg', 'a43171012603cf7d4f0fb8499877438b'),
        ('005', 6, 350, 0, 'cabin-005.jpg', 'd55d7b511fe1b28560b448969f4ebf5e'),
        ('006', 6, 800, 100, 'cabin-006.jpg', '6ac44400e7acee91de84591087af5bb1'),
        ('007', 8, 600, 100, 'cabin-007.jpg', 'b23385d3c779dadc63b297ed2405d9cd'),
        ('008', 10, 1400, 0, 'cabin-008.jpg', '1ad1a84db2db8ec2b3378acb33ebf7cd')
    ) AS expected(
      name,
      max_capacity,
      regular_price,
      discount,
      object_name,
      description_md5
    )
    LEFT JOIN public.cabins AS cabin
      ON cabin.name = expected.name
      AND cabin.demo_dataset = dataset_marker
      AND cabin."maxCapacity" = expected.max_capacity
      AND cabin."regularPrice" = expected.regular_price
      AND cabin.discount = expected.discount
      AND md5(cabin.description) = expected.description_md5
      AND cabin.image = image_base_url || expected.object_name
    WHERE cabin.id IS NULL
  )
  THEN
    RAISE EXCEPTION
      'Recruiter demo reset validation failed: canonical cabin identity, pricing, capacity, or image mapping differs';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM generate_series(1, 24) AS expected(sequence_number)
    LEFT JOIN public.guests AS guest
      ON guest."nationalID" =
        'DEMO-' || lpad(expected.sequence_number::text, 4, '0')
      AND guest.demo_dataset = dataset_marker
    WHERE guest.id IS NULL
  ) OR EXISTS (
    SELECT 1
    FROM public.guests
    WHERE demo_dataset = dataset_marker
      AND email !~ '^[a-z.]+@example[.]test$'
  )
  THEN
    RAISE EXCEPTION
      'Recruiter demo reset validation failed: synthetic guest identity contract differs';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.cabin_image_cleanup_queue AS queue
    WHERE queue.object_name !~ owned_object_pattern
      OR queue.object_name IN (
        'cabin-001.jpg', 'cabin-002.jpg', 'cabin-003.jpg', 'cabin-004.jpg',
        'cabin-005.jpg', 'cabin-006.jpg', 'cabin-007.jpg', 'cabin-008.jpg'
      )
      OR EXISTS (
        SELECT 1
        FROM public.cabins AS cabin
        WHERE cabin.image = image_base_url || queue.object_name
      )
  )
  THEN
    RAISE EXCEPTION
      'Recruiter demo reset validation failed: cleanup queue contains an invalid, permanent, or referenced image';
  END IF;
END
$reset_function$;

REVOKE ALL ON FUNCTION private.reset_recruiter_demo_data() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.reset_recruiter_demo_data() FROM anon;
REVOKE ALL ON FUNCTION private.reset_recruiter_demo_data() FROM authenticated;

COMMIT;
