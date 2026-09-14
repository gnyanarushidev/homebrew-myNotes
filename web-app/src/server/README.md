# MyNotes server logic

Server-only TypeScript services live inside the Next.js application and are imported by routes in `src/app/api/`. One package, build, environment file, and Vercel deployment serve the entire web application.

## Current entry points

- `@/server/health`: application liveness, exposed at `/api/v1/health`.
- `@/server/auth/`: verified account/admin access, HTTP-only sessions, and auth settings.
- `@/server/http`: authenticated API requests, same-origin JSON body limits, and private responses.
- `@/server/service`: server-secret Supabase client, account listing, and recovery eligibility.

Notebook CRUD lives at `/api/notebooks`; admin account management lives at `/api/admin/users`. The notebook table denies all direct browser access through table grants and default-deny RLS. Service-role queries must include the verified user's immutable `owner_id`; admin access does not bypass notebook ownership. See the [application README](../../README.md) and `supabase/migrations/001_notebooks.sql` for deployment.

The health response confirms that the application is running. It does not check Supabase or Backblaze connectivity.

## Module boundaries

- Import `server-only` in each server entry point to prevent accidental use in a Client Component.
- Import server services through the `@/server/` path alias.
- Keep HTTP request/response handling in `src/app/api/` routes.
- Add authentication and ownership checks alongside each protected feature.
- Read runtime environment settings from the Next.js application environment at `web-app/.env.local` locally and Vercel project settings when deployed.

Upcoming modules follow `PROJECT_PLAN.md`: invitation lifecycle/audit data, shared drawing compatibility, synchronization, file storage, and native imports. Current notebook revisions are whole-document compare-and-swap values, not a synchronization change feed.
