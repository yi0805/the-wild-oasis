# The Wild Oasis

The Wild Oasis is a hotel operations dashboard for managing cabins, bookings, check-in/check-out, hotel settings, and user profiles. It is an engineering portfolio project focused on React and TypeScript architecture, client-side server-state handling, reliable mutations, Supabase security boundaries, automated regression tests, and CI.

**Stack:** React 18 · TypeScript · Vite · Supabase · TanStack Query · React Hook Form · Vitest / React Testing Library · GitHub Actions · Vercel

[![CI](https://github.com/yi0805/the-wild-oasis/actions/workflows/ci.yml/badge.svg)](https://github.com/yi0805/the-wild-oasis/actions/workflows/ci.yml)

## Live deployment

[Open the Vercel deployment](https://17-the-wild-oasis-blond.vercel.app)

Public sign-up is disabled. A dedicated reviewer account is available, with credentials shared privately on request and never stored in this repository. The hosted demo dataset resets automatically each day.

### Reviewer demo

The hosted application uses a dedicated recruiter-safe demo dataset. A guarded PostgreSQL reset function runs through Supabase Cron each day at 00:05 UTC, restoring the canonical cabin, guest, booking, and settings data after reviewer use.

Public sign-up remains disabled. Reviewer credentials are shared privately on request and are not stored in the repository.

## Screenshots

### Dashboard

![The Wild Oasis operations dashboard with key metrics, stay activity, and sales charts](docs/screenshots/dashboard.png)

### Bookings

![Booking management table with operational statuses and filtering controls](docs/screenshots/bookings.png)

### Cabins

![Cabin management table with imagery, capacity, pricing, and operational actions](docs/screenshots/cabins.png)

## Engineering highlights

- TypeScript/TSX is used throughout the active production application graph, with generated Supabase database contracts at the data boundary.
- Feature hooks coordinate [TanStack Query](https://tanstack.com/query/latest) queries and targeted mutation invalidation; React Hook Form handles operational forms.
- Supabase Auth, PostgreSQL RLS/grants, and Storage policies form the authorization boundary for a simple trusted-operator model.
- A guarded PostgreSQL reset function and Supabase Cron job restore the canonical recruiter-demo dataset daily; browser roles cannot invoke the reset directly.
- Storage-backed cabin and avatar mutations use explicit ordering and best-effort compensation for failed follow-up writes.
- Vitest and React Testing Library cover behavioural workflows and service-level mutation failures; GitHub Actions runs lint, typecheck, tests, and the production build.
- Important query boundaries render explicit loading, failure, and appropriate empty states; key modal/menu workflows have keyboard and focus handling, with targeted responsive layouts for forms, Dashboard, and booking/check-in workflows.
- Measured route-level code splitting reduced the initial production entry bundle from 284.19 kB gzip to 138.82 kB gzip on the same local build environment.
- The active deployment is hosted on Vercel.

## What the application supports

- Dashboard metrics and stay activity
- Booking browsing, detail, deletion, and check-in/check-out workflows
- Cabin creation, editing, duplication, and deletion
- Hotel setting updates
- Profile, password, and avatar updates

## Architecture

```text
React / TypeScript UI
        ↓
Feature hooks + TanStack Query
        ↓
Service layer
        ↓
Supabase
├── Auth
├── PostgreSQL + RLS/grants
└── Storage + policies
```

Route-level pages compose feature and reusable UI components. `services/` is the Supabase data-access boundary; feature hooks own query and mutation orchestration. Supabase is the backend—there is no separate API service.

## Security model

The product uses a trusted-operator model:

```text
Unauthenticated → no operations-data access
Authenticated   → trusted operations user with shared hotel data access
```

This is intentionally not an admin/staff RBAC system. Browser sign-up is disabled, while Supabase Auth plus database RLS/grants and Storage policies authorize the actual data operations. `ProtectedRoute` only controls client-side navigation and is not the authorization boundary.

The verified table boundary grants authenticated users only the application operations they need: bookings can be read, updated, and deleted (not inserted); cabins have CRUD access; guests are read-only; and settings can be read or updated only for `id = 1`. Anonymous users have no application-table privileges. The `avatars` and `cabin-images` buckets intentionally use public delivery URLs, but mutation access is policy controlled. See the [current Supabase security baseline](docs/supabase/current-security-baseline.md) for the detailed evidence and policy history.

## Reliability examples

**Cabin images.** A new image is uploaded before the cabin database write, so an upload failure leaves an existing cabin unchanged. If the subsequent create or edit write fails, the service makes a best-effort attempt to remove the newly uploaded object. After a successful replacement, cleanup is limited to a strictly canonical application-owned old URL that no cabin still references; it is queued before deletion and failed deletion remains available for a bounded retry on the Cabins page. Historical/default images, cabin-delete cleanup, and guaranteed background processing remain out of scope.

**Avatars.** The service first resolves the authoritative Auth user, uploads a new avatar, then persists the requested profile metadata and avatar URL in one Auth update. If that update fails, it attempts to remove the new object. After success, it deletes the previous avatar only when it is clearly an application-owned object for that same user; malformed, external, unrelated, and other-user URLs are never deleted. Hosted verification covered successful replacement and previous-object removal.

## Testing and CI

The current suite contains **34 test files and 183 tests**. It uses Vitest, React Testing Library, and focused local Supabase/Storage mocks—tests target observable workflows and service failure behaviour rather than component implementation details.

The [GitHub Actions workflow](.github/workflows/ci.yml) runs `npm ci`, lint, typecheck, tests, and the production build on pull requests to `main` and pushes to `main`.

## Engineering evolution

The original application provided the hotel-dashboard product baseline as part of a course/tutorial. This repository does not present that baseline product functionality as independently invented from scratch.

The portfolio work independently improved its engineering quality through configuration and credential hygiene; mutation-failure handling; Supabase Auth/RLS/Storage review and hardening; browser-sign-up removal; behavioural regression tests; GitHub Actions CI; generated Supabase TypeScript contracts; an incremental TypeScript migration; explicit production query-state handling; targeted modal/menu accessibility and responsive workflows; avatar lifecycle safety; and supporting engineering documentation. The [roadmap](ROADMAP.md) and [task handoffs](docs/handoff/) record the scope and verification for those changes.

## Local setup

Install locked dependencies:

```bash
npm ci
```

Create a local environment file from [.env.example](.env.example) and supply:

```text
VITE_SUPABASE_URL=
VITE_SUPABASE_PUBLISHABLE_KEY=
```

These are public browser-client configuration values. Do not add a Supabase service-role key to Vite configuration or the client application.

Start the development server:

```bash
npm run dev
```

## Commands

| Command | Purpose |
| --- | --- |
| `npm run dev` | Start the Vite development server |
| `npm run lint` | Run ESLint |
| `npm run typecheck` | Run TypeScript checking |
| `npm test` | Run the Vitest suite |
| `npm run build` | Build the production bundle |
| `npm run preview` | Preview the production build |

## Deployment

Vercel is the verified active deployment platform. The production URL is [https://17-the-wild-oasis-blond.vercel.app](https://17-the-wild-oasis-blond.vercel.app). [vercel.json](vercel.json) rewrites application paths to the SPA entry point.

## Known limitations and deferred work

- Public Storage delivery URLs are intentional. Browser and service upload validation allow only JPEG, PNG, and WebP files up to 5,242,880 bytes; human SQL verification confirmed matching hosted enforcement for both existing Storage buckets.
- Cabin-image cleanup applies only to canonical, currently unreferenced replacement objects; historical/legacy images and cabin-delete cleanup remain out of scope, and retries run only during bounded Cabins-page lifecycle passes rather than guaranteed background processing.
- Two moderate React Router v6 advisories remain; the available remediation is an intentionally deferred breaking v7 upgrade.
- Route-level splitting removes the prior large initial-entry warning, but no bundle budget or further dependency-level performance analysis has been established.
- Responsive and accessibility hardening is targeted to important workflows; it is not a full WCAG or cross-device certification.
- Supabase security migrations were manually applied through the SQL Editor. Hosted Supabase CLI migration history is not reconciled, so `supabase db push` should not be assumed safe.
