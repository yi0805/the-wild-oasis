# Task

032 — Canonical recruiter demo dataset and safe reset function

Branch: `task/032-recruiter-demo-reset`

Verified base `main` SHA: `30a66561f6b0ed48be490f66aee1f882459e24fc`

Stage: B — hosted reset and verification complete

## Goal

Provide one privacy-safe, UTC-relative recruiter dataset and one atomic, repeatable PostgreSQL reset function for the designated disposable Supabase demo environment. Supabase Cron is explicitly deferred to Task 033.

## Changed

- Added `supabase/migrations/20260928000000_recruiter_demo_reset.sql` as the reviewed manual-SQL-Editor migration. Its original revision was applied to hosted Supabase; the repository copy now contains the numeric-arithmetic correction for future clean environments and must not be rerun on the current project.
- The migration adds nullable `demo_dataset` markers to `cabins`, `guests`, and `bookings`. Canonical rows use `recruiter-v1`.
- The one-time legacy designation refuses to run unless the freshly audited legacy baseline still has exactly 8 cabins, 32 guests, 24 bookings, and the single settings row `id = 1` with values `3/90/8/15`. It verifies all 30 historical tutorial identities through field-complete digests, the exact confirmed test identities at IDs 95 and 96, the audited 20 linked / 12 unmatched guest relationship distribution, the exact eight cabin identities/capacity/pricing/description hashes/image URLs, booking foreign keys, and initially empty marker columns before marking existing operational rows.
- New cabins default to `recruiter-v1`. This is the smallest database-side change that makes cabins created or duplicated through the reviewer UI removable by the next reset without exposing the marker in forms or UI. Guests and bookings retain null defaults because the browser has no insert grant/path for them.
- Added `private.reset_recruiter_demo_data()` as a `SECURITY INVOKER` function in a non-public schema. It takes a transaction-scoped advisory lock, uses `(statement_timestamp() AT TIME ZONE 'UTC')::date`, deletes only `recruiter-v1` bookings/guests/cabins in foreign-key order, resolves newly inserted IDs through cabin names and synthetic national IDs, restores settings in place, and validates the complete result before returning.
- Revoked private-schema usage and function execution from `PUBLIC`, `anon`, and `authenticated`. The function does not use `SECURITY DEFINER`; SQL Editor/database-owner execution and a later database-internal scheduler do not require elevated browser-callable behavior.
- Added exactly 8 established cabins, 24 fictional guests with `@example.test` emails and `DEMO-0001` through `DEMO-0024` national IDs, and 24 bookings (three per cabin). Booking prices are derived from inserted cabin pricing and the canonical breakfast price rather than duplicated constants.
- The booking distribution includes 8 checked-out, 6 checked-in, and 10 unconfirmed rows; 16 paid and 8 unpaid rows; 13 with breakfast and 11 without; two UTC-today arrivals and two UTC-today departures; multiple stay-duration buckets; and booking creation dates that populate the Dashboard 7/30/90-day filters.
- Added `supabase/verification/task_032_recruiter_demo_reset_dry_run.sql` with privilege inspection, two reset calls inside one transaction, result queries, consistency queries, and `ROLLBACK`.
- Added `supabase/repairs/20260928010000_recruiter_demo_reset_numeric_repair.sql` for the already-applied hosted migration. It preflights the marked `8/32/24` state, replaces only the existing function with widened price arithmetic, reapplies browser-role revocations, validates the function security boundary, and never invokes the reset.
- All cabin-price, breakfast-extras, and total-price arithmetic now casts operands to `numeric` before subtraction, multiplication, or addition in the seed, function validation, and independent dry-run validation. The dry-run contains an executable Cabin 008 regression requiring the 30-night and 31-night rows to calculate `42000` and `43400` without overflow.
- Added `supabase/verification/task_032_recruiter_demo_reset_post_apply.sql`, a read-only reusable hosted verification query covering counts, settings, booking distributions, integrity, arithmetic, overlaps, markers, canonical images, cleanup entries, Auth/avatar snapshots, and function privileges.
- Regenerated `src/types/database.types.ts` from the hosted public schema. Its only schema-contract additions are nullable `demo_dataset` fields for `cabins`, `guests`, and `bookings` Row/Insert/Update types.
- Updated `ROADMAP.md` with the completed Task 032 hosted state and Task 033 dependency.

## Not Changed

- The user manually applied the original migration, explicitly rolled back the first failed dry run, applied the numeric repair, and completed the corrected dry run without error. Codex then ran the approved permanent reset once after an independent read-only preflight.
- Auth users, passwords, Auth metadata, avatars, Storage objects, RLS intent, table grants, Storage policies, bucket settings, public signup, service-role handling, and frontend date behavior are unchanged.
- The eight canonical `cabin-001.jpg` through `cabin-008.jpg` objects are not uploaded, deleted, or eligible for queueing.
- JavaScript tutorial fixtures remain historical/development residue and were not updated or used as another canonical dataset. The hosted PostgreSQL reset is the canonical recruiter dataset.
- No Cron, Edge Function, reviewer credential, RBAC, router/dependency change, unrelated settings change, or Auckland timezone model was added.

## Design Decisions

### Disposable hosted designation

The user confirmed that the hosted project contains portfolio/test/demo data only: the two non-fixture guest rows identified as IDs 95 and 96 are test data; all three Auth users are test/operator accounts; no real customer data needs preservation; `cabin-images` now contains only the eight canonical cabin assets; every cabin row references its corresponding asset; and `avatars` contains only the two objects referenced by Auth metadata. Task 032 therefore treats operational cabin/guest/booking rows as disposable recruiter-demo data while deliberately leaving Auth and avatars untouched.

A fresh read-only hosted dump on 2026-09-28 confirmed 8 cabins, 32 guests, 24 bookings, one settings row, and an empty cleanup queue. All 30 historical `src/data/data-guests.js` identities match hosted rows exactly. Twenty distinct guests are booking-linked. The 12 unmatched guest IDs are `66, 67, 69, 70, 88, 89, 90, 91, 92, 93, 94, 96`: 11 are historical tutorial rows and ID 96 is one of the two confirmed test rows. The only non-fixture rows are IDs 95 and 96; ID 95 is currently booking-linked. Both still exist and match the audited identities.

The audit also found that hosted Cabin 001 has `regularPrice = 200`, whereas the historical JavaScript cabin fixture says `250`. The canonical SQL preserves the current hosted value `200`; the other seven hosted capacity/pricing rows match the historical fixture. The JavaScript fixture remains historical residue and is not another canonical seed source.

### UTC date anchor

`src/utils/helpers.ts` establishes the active frontend contract by setting UTC start/end-of-day values, and Today Activity compares those values to booking timestamps. The reset uses the same UTC calendar day. No global database timezone or frontend business-timezone behavior changes.

### Storage cleanup boundary

Before deleting marked cabins, the function captures only exact public URLs at this project's `cabin-images` origin whose object names match the existing application-owned UUID-v4 convention: `cabin-<uuid-v4>.(jpg|png|webp)`. After canonical cabins are recreated, it queues only captured objects with no remaining cabin reference, using the existing durable cleanup queue. Fixed `cabin-001.jpg` through `cabin-008.jpg` names cannot match the ownership pattern and are validated as absent from the queue. The function never writes `storage.objects` and never touches avatars. Cleanup execution remains the existing bounded application retry behavior.

### Settings

The reset requires exactly one settings row with `id = 1` and updates that row in place to `minBookingLength = 3`, `maxBookingLength = 90`, `maxGuestsPerBooking = 8`, and `breakfastPrice = 15`. It never deletes/reinserts settings.

## Hosted Apply and Reset Result

The project retains its intentionally unreconciled historical CLI migration history, so no `supabase db push` was run. The reviewed files were applied through the manual SQL Editor workflow:

1. The user applied the migration. Its one-time guard designated the verified legacy demo population.
2. The first dry run exposed PostgreSQL `smallint` overflow in validation and was explicitly rolled back.
3. The user applied the function-only numeric repair and ran the corrected dry run without error. Its final rollback restored `8/32/24/1/0`.
4. Codex independently confirmed the repaired function, markers, privileges, canonical images, settings, and rolled-back baseline through read-only Management API queries.
5. Codex invoked `private.reset_recruiter_demo_data()` once as one atomic statement and then ran the read-only post-apply verification.
6. When delivery resumed on 2026-09-29 UTC after an interrupted turn, a read-only check showed the prior day's otherwise-valid dataset had naturally moved past its Today Activity anchors. Codex invoked the reviewed reset once more and repeated the post-apply verification so the delivered hosted state is anchored to 2026-09-29 UTC.

The audited pre-reset baseline was:

- cabins: 8;
- guests: 32 (all 30 historical fixture identities plus confirmed test rows 95 and 96);
- bookings: 24;
- distinct booking-linked guests: 20;
- unmatched guests: IDs `66, 67, 69, 70, 88, 89, 90, 91, 92, 93, 94, 96`;
- settings: 1, with id 1 and values `3/90/8/15`;
- cleanup queue: 0.

After migration and corrected dry-run rollback:

- marked cabins/guests/bookings: `8/32/24`;
- the same operational data remains; only marker columns/default and the private function/schema are added.

The user-confirmed dry run produced the canonical result and rolled it back. The permanent reset subsequently produced the same result:

- marked cabins/guests/bookings: `8/24/24`;
- status counts: checked-out 8, checked-in 6, unconfirmed 10;
- paid/unpaid: 16/8;
- breakfast true/false: 13/11;
- UTC-today arrivals/departures: 2/2;
- Dashboard-created booking counts for 7/30/90 days: 9/18/23;
- every invalid/orphan/overlap/capacity/arithmetic/synthetic-marker count: 0;
- settings: the single id 1 row with values `3/90/8/15`;
- browser schema/function privilege booleans and `security_definer`: all `false`;
- cleanup queue: 0.

The final hosted state is the permanent canonical `8/24/24` dataset. The reset remains atomic: any raised validation exception rolls back the statement, and the function contains no transaction control.

## Verification

- Repository gate: clean local `main` fetched/pulled fast-forward-only and matched `origin/main` at `30a66561f6b0ed48be490f66aee1f882459e24fc`; Task 031 is merged as `e95dd8e` / PR #32 and Phase 2 is complete.
- Hosted read-only type inspection with Supabase CLI 2.116.0 found no existing generated objects in a `private` schema. A subsequent data-only public-schema dump through the CLI's temporary read-only login confirmed the exact audit state described above. No hosted schema/data mutation or migration-history command was run.
- PostgreSQL parser/execution checks accepted the corrected migration, standalone repair, and dry-run verification files.
- An ephemeral PostgreSQL-compatible in-memory test applied the migration to an exact local mirror of the audited `8/32/24` hosted rows, verified the `8/32/24` designation, ran the reset twice, and produced `8/24/24`, Cabin 001 at `$200`, two UTC-today arrivals, two UTC-today departures, and an empty queue.
- The complete dry-run verification file executed against that local mirror and its final rollback restored the original `8/32/24` counts.
- A tampered local copy changed one historical guest identity; the strengthened 30-fixture-identity guard raised and an explicit rollback left all three marker columns absent, proving the one-time designation fails atomically rather than classifying an unknown population.
- The same test inserted a reviewer-created marked cabin with an exact app-owned UUID image, ran the reset again, and found exactly that orphan object in the existing cleanup queue.
- The isolated test confirmed `anon` and `authenticated` both lacked private-schema usage and reset-function execution.
- A smallint-accurate isolated schema reconstructed the original un-widened function and reproduced `smallint out of range` on Cabin 008. The standalone hosted repair then replaced only that function; the complete dry-run passed and rolled back; two subsequent local resets produced `8/24/24`; and Cabin 008's 30-night/31-night cabin prices were exactly `42000/43400`.
- The user reported that the hosted function-only repair succeeded, the corrected hosted dry run completed without error, and its final rollback restored `8 cabins / 32 guests / 24 bookings / 1 settings row / 0 cleanup entries`.
- Immediately before the permanent reset, a read-only hosted preflight independently confirmed the same `8/32/24/1/0` baseline; all three marker columns; numeric-safe seed and validation expressions; `SECURITY INVOKER`; locked `search_path`; and no schema usage or function execution for `PUBLIC`, `anon`, or `authenticated` as applicable.
- The permanent hosted reset completed as one function statement. The read-only post-apply verification returned `8 cabins / 24 guests / 24 bookings / 1 settings row / 0 cleanup entries`; settings `3/90/8/15`; booking status `8/6/10`; paid/unpaid `16/8`; breakfast true/false `13/11`; UTC-today arrivals/departures `2/2`; Dashboard 7/30/90-day counts `9/18/23`; and Cabin 008 prices `42000/43400` for 30/31 nights.
- The same post-apply query passed after the final 2026-09-29 UTC refresh, demonstrating repeatability across a UTC calendar-day boundary.
- All hosted invalid counts were zero: orphan FKs, unsupported statuses, invalid dates/nights/guest counts, capacity, price arithmetic, overlaps, unmarked rows, synthetic identities, canonical cabin images, and cleanup queue entries.
- `cabin-images` retained exactly `cabin-001.jpg` through `cabin-008.jpg`. Auth retained three users. The avatar bucket retained its zero-byte `.emptyFolderPlaceholder` plus the same two Auth-referenced objects; Auth-metadata and avatar-object digests were identical before and after the reset.
- An authenticated-role read simulation using an existing operator subject and no mutations saw `8/24/24/1`, all 24 joined booking rows, four Today Activity rows, and 23 Dashboard 90-day rows. The deployed Vercel root, `/login`, `/dashboard`, and `/bookings` all returned HTTP 200 with the application HTML. No account credential was available or changed, so a real interactive signed-in browser session was not performed.
- Supabase CLI 2.116.0 regenerated the hosted public-schema TypeScript contract. The diff adds only nullable `demo_dataset` properties to `cabins`, `guests`, and `bookings` Row/Insert/Update types.
- `npm ci`: passed; existing transitive deprecation notices and the full development-dependency audit summary were printed.
- `npm run lint`: passed with zero warnings.
- `npm run typecheck`: passed.
- `npm test -- --reporter=dot`: passed, 34 files / 183 tests. Expected test-path error logging and React Router v7 future-flag notices were printed without failures.
- `npm run build`: passed. The route-split output retained a 463.58 kB minified / 138.93 kB gzip initial entry and no large-chunk warning.
- `git diff --check`: passed; Git printed only the repository's existing LF-to-CRLF working-copy notice for `ROADMAP.md`.
- `npm audit --omit=dev`: completed with the two documented moderate React Router v6 advisories; the offered remediation remains the intentionally deferred breaking React Router v7 upgrade.
- Hosted function repair, corrected dry run, permanent reset, post-apply verification, generated-type regeneration, and application-data checks are complete.

## Risks / Notes

- The original migration and one-time repair are already applied and must not be rerun on the current hosted project.
- The canonical project URL is public configuration and is intentionally explicit so resets still restore cabin URLs even if reviewers edit/delete all cabin rows.
- The reset queues eligible Storage orphans but does not delete them directly. Actual cleanup remains best-effort when the Cabins page processes the existing queue.
- Existing Supabase CLI migration history remains unreconciled; continue using the manual SQL Editor workflow.
- Task numbering is user-directed and overlaps the earlier historical `task_032_phase_3_recruiter_readme.md`; the distinct branch and handoff filename identify this recruiter-reset task.
- Interactive authenticated browser verification remains limited by the absence of an available account credential; authenticated database-role reads and the existing automated application workflow suite provide the recorded coverage instead.

## Next

After Task 032 review and human merge, proceed separately to Task 033 — Supabase daily Cron plus reviewer access verification. No Cron work is included here.
