# MyNotes server logic

Server-only TypeScript services live inside the Next.js application and are imported by routes in `src/app/api/`. One package, build, environment file, and Vercel deployment serve the entire web application.

## Current entry points

- `@/server/health`: application liveness, exposed at `/api/v1/health`.
- `@/server/auth/`: verified account/admin access, HTTP-only sessions, and auth settings.
- `@/server/http`: authenticated API requests, same-origin JSON body limits, and private responses.
- `@/server/service`: server-secret Supabase client, account listing, and recovery eligibility.
- `@/server/cloud`: metadata manifests, transactions/receipts, account change feed and legacy JSONB migration.
- `@/server/storage`: private B2 staging, validation, gzip page objects, signed downloads and reference-aware cleanup.

The shared file/sync protocol lives at `/api/v1/sync`; `/api/notebooks` remains a small-document compatibility interface. Admin management lives at `/api/admin/users`. Metadata tables deny direct browser access through grants and default-deny RLS. Service-role queries include the verified immutable `owner_id`; administrator status does not bypass notebook ownership. Apply `002_cloud_storage.sql` and follow the repository's authoritative `PROJECT_PLAN.md`.

The health response confirms that the application is running. It does not check Supabase or Backblaze connectivity.

## Module boundaries

- Import `server-only` in each server entry point to prevent accidental use in a Client Component.
- Import server services through the `@/server/` path alias.
- Keep HTTP request/response handling in `src/app/api/` routes.
- Add authentication and ownership checks alongside each protected feature.
- Read runtime environment settings from the Next.js application environment at `web-app/.env.local` locally and Vercel project settings when deployed.

Current publication uses whole-notebook compare-and-swap revisions, independent page objects and an account-serialized change sequence. Later work includes finer page merging, bounded stale-device/operation retention, invitation lifecycle auditing and dense-document performance.
