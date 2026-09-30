# Task

033 — Daily Supabase Cron and reviewer access verification

Branch: `task/033-supabase-cron-reviewer-access`

Verified base `main` SHA: `3363b263f7972b6a666df37110ad7bdb8c4cdd7c`

Stage: Complete — Stage A repository preparation and Stage B hosted verification are complete

## Goal

Schedule the reviewed recruiter-data reset once per day shortly after UTC midnight, prove that the schedule is secure, observable, and reversible, and establish a safe reviewer-login workflow without committing or exposing credentials.

The implemented architecture is direct database execution:

```text
pg_cron at 00:05 UTC
  -> SELECT private.reset_recruiter_demo_data();
```

## Changed

- Added `supabase/cron/20260929000000_recruiter_demo_daily_reset.sql`, the manually applied, transactional, fail-closed Cron installer.
- The installer uses the stable job name `recruiter-demo-daily-reset`, schedule `5 0 * * *`, and exact command `SELECT private.reset_recruiter_demo_data();`.
- The installer verifies the reviewed Task 032 function definition and security boundary, required Cron objects and UTC configuration, installer/function-owner alignment, database and execution-role compatibility, a safe installation time, and absence of conflicting jobs before scheduling.
- The installer verifies the stored job metadata after scheduling. Any installation failure rolls back schedule creation.
- Preserved the exact guarded rollback/unschedule block as comments in the installer. It removes only the same-named job when its schedule, command, database, and execution role still match the reviewed installation.
- Added `supabase/verification/task_033_recruiter_demo_cron.sql`, a read-only verification script for Cron configuration, job metadata, duplicate/conflict counts, run history, reset-function security, canonical data, integrity counts, and non-secret aggregate Auth metadata.
- Updated `ROADMAP.md` to mark Task 033 complete and record the real scheduler execution and credential-free reviewer workflow verification.
- The human enabled Supabase Cron, manually applied the reviewed installer, created a dedicated owner-controlled reviewer account through Supabase Dashboard admin tooling, and completed the approved hosted and interactive verification.

## Not Changed

- The reset function, application source, database schema, RLS policies, Storage policies, buckets, and public signup configuration were not changed by Task 033.
- The production Cron schedule was not accelerated or changed for testing, and the reset was not invoked manually during Task 033.
- The reviewed Cron job was not altered, deactivated, or unscheduled after installation.
- No reviewer email, password, user ID, bearer token, or other identity or credential data was retrieved, printed, recorded, or committed.
- No existing operator credential was changed. Public signup remains disabled.
- No frontend credential, signup path, RBAC layer, Edge Function, HTTP Cron call, `pg_net`, Vault secret, service-role key, or standalone backend was added.
- Supabase CLI migration history remains intentionally unreconciled. `supabase db push` was not run.
- The Pull Request is intentionally left unmerged for independent review and human merge authority.

## Hosted Verification

### Cron installation

The human enabled Supabase Cron / `pg_cron` and manually applied the reviewed installer through the approved SQL Editor workflow.

The installed job was verified as:

- job name: `recruiter-demo-daily-reset`;
- schedule: `5 0 * * *`;
- command: `SELECT private.reset_recruiter_demo_data();`;
- database: `postgres`;
- execution role: `postgres`;
- active: `true`.

Conflict verification returned:

- intended name count: 1;
- exact active job count: 1;
- all reset-job count: 1;
- unexpected reset-job count: 0.

### Real scheduler execution

The first natural production Cron execution occurred at `2026-09-30 00:05 UTC`. The production schedule was not changed or accelerated for testing, and the reset was not invoked manually.

`cron.job_run_details` recorded:

- job: `recruiter-demo-daily-reset`;
- execution role: `postgres`;
- command: `SELECT private.reset_recruiter_demo_data();`;
- status: `succeeded`;
- return message: `1 row`.

This is real pg_cron scheduler evidence, distinct from the prior Task 032 manual reset proof and the Task 033 installation proof.

### Post-Cron canonical state

After the real scheduler run, the complete Task 032 post-apply verification returned:

- 8 cabins, 24 synthetic guests, 24 bookings, 1 settings row, and 0 cleanup-queue entries;
- settings `3 / 90 / 8 / 15`;
- booking statuses: 8 checked-out, 6 checked-in, and 10 unconfirmed;
- paid/unpaid: 16 / 8;
- breakfast/no breakfast: 13 / 11;
- Today Activity: 2 arrivals / 2 departures;
- Dashboard 7/30/90-day counts: 9 / 18 / 23;
- Cabin 008 30-night/31-night prices: 42000 / 43400;
- exactly `cabin-001.jpg` through `cabin-008.jpg` in cabin Storage.

Every invalid counter was zero: orphan bookings, unsupported statuses, invalid booking shape, over-capacity bookings, invalid prices, overlaps, unmarked cabins/guests/bookings, invalid synthetic guests, invalid canonical cabins, and invalid cleanup entries.

The reset function remains owned and executed through the reviewed database boundary:

- `SECURITY INVOKER`;
- `search_path=pg_catalog, public`;
- `PUBLIC` execute: false;
- `anon` private-schema usage: false;
- `authenticated` private-schema usage: false;
- `anon` execute: false;
- `authenticated` execute: false.

### Reviewer workflow

The human chose the owner-controlled dedicated reviewer-account workflow and created the account manually through Supabase Dashboard admin tooling. No identity or credential value is included in this repository or handoff.

Using a private browser session, the human verified:

- reviewer login succeeded;
- Dashboard loaded and Today Activity displayed correctly;
- Bookings, Cabins, Settings, and Account loaded;
- after logout, protected routes behaved correctly for the unauthenticated session;
- public signup remains disabled.

The aggregate Auth user count is now 4 because of the intentionally created reviewer account. The avatar object count remains unchanged at 3. The function privilege checks above confirm that an authenticated reviewer cannot use the private schema or execute the reset.

## Rollback / Unschedule

Use only the reviewed commented rollback block at the bottom of `supabase/cron/20260929000000_recruiter_demo_daily_reset.sql`, run separately in SQL Editor as `postgres`.

The block:

1. requires the Cron table and named `cron.unschedule(text)` function;
2. requires exactly one `recruiter-demo-daily-reset` row;
3. refuses removal unless schedule, command, database, and execution role still match the reviewed job;
4. calls `cron.unschedule('recruiter-demo-daily-reset')`; and
5. verifies that the named job no longer exists before commit.

After rollback, rerun the read-only verification and confirm the intended job query returns zero rows. Leave the `pg_cron` extension enabled unless disabling the whole module is separately approved: disabling it deletes every Cron job and is broader than this task's rollback.

## Verification

- Repository gate: fetched `origin --prune`, checked out `main`, pulled fast-forward-only, confirmed a clean tree, and confirmed `HEAD == origin/main == 3363b263f7972b6a666df37110ad7bdb8c4cdd7c` before creating the task branch.
- Stage A hosted audit: confirmed the Task 032 data/security baseline, absence of an existing Cron installation/job, public-signup state, and the need for a dedicated reviewer account without returning identity data.
- SQL installer: previously exercised against an isolated PGlite/PostgreSQL-compatible mock. Missing capability and duplicate installation failed closed; the success path stored the exact intended job without invoking the reset; and the guarded rollback removed only the matching job without invoking the reset.
- SQL verification file: previously executed successfully against the isolated schema/job mock and then used for the human-completed hosted verification.
- Hosted Cron installation: passed with exactly one intended active job and no conflicting reset job.
- Real scheduler execution: passed at `2026-09-30 00:05 UTC` with status `succeeded` and return message `1 row`.
- Post-Cron Task 032 verification: passed with the canonical counts, distributions, prices, Storage objects, zero invalid counters, and locked function boundary recorded above.
- Reviewer workflow: passed through a private browser session without recording identity or credential data.
- `npm ci`: passed; installed 493 packages and audited 494. Existing transitive deprecation notices and the full dependency-tree total of 17 vulnerabilities were reported.
- `npm run lint`: passed with zero warnings.
- `npm run typecheck`: passed.
- `npm test -- --reporter=dot`: final exact-command run passed, 34 files / 183 tests. Two earlier full runs each had one different 5-second timeout in the unchanged `CreateCabinForm` test file; the focused file passed 10/10 and the subsequent exact full run passed without a code change. Expected test-path error logging and React Router v7 future-flag notices were printed without failures in the passing run.
- `npm run build`: passed. The route-split output retained a 463.58 kB minified / 138.93 kB gzip initial entry and no large-chunk warning.
- `git diff --check`: passed; Git printed only the repository's existing LF-to-CRLF working-copy notice for `ROADMAP.md`.
- `npm audit --omit=dev`: completed with exit code 1 because of the two existing moderate React Router v6 advisories. The offered automatic remediation is a breaking React Router v7 upgrade and remains outside Task 033.

## Risks / Notes

- The installer pins the hosted Task 032 function definition MD5. Any intentional reset-function change requires independent review and a corresponding guard update; bypassing the guard is not acceptable.
- `cron.schedule(job_name, ...)` can overwrite a same-named job for the same role. The installer avoids that behavior by refusing an existing name or another job targeting the reset function.
- Cron uses the configured timezone. The installer accepts only `GMT` or `UTC`, keeping `5 0 * * *` fixed at 00:05 UTC.
- Reviewer access has the application's existing trusted-operator permissions; Task 033 does not add staff/admin RBAC. Account expiry or removal remains an owner operational responsibility.
- The final test gate passed, but the two preceding full-suite attempts exposed timing sensitivity in different tests within the unchanged `CreateCabinForm` file. The focused file and final full suite both passed without code changes.
- The production dependency audit retains two moderate React Router v6 advisories whose automatic fix requires the out-of-scope breaking v7 upgrade.
- Supabase CLI migration history remains unreconciled. Continue using the documented manual SQL Editor workflow and do not run `supabase db push`.
- The Cron job remains active in production by design. The guarded unschedule procedure above is available if the human later decides to remove it.

## Next

Obtain independent review of the completed Pull Request. Leave it unmerged until the human makes the final merge decision. Do not begin another task as part of this closeout.
