# MyNotes backend package

This is a server-only TypeScript workspace package consumed by Next.js API routes in `../frontend/`. Next.js transpiles and deploys it as part of the web application.

## Current entry point

- `@mynotes/backend/health`: application liveness, exposed at `/api/v1/health`.

The health response confirms that the application is running. It does not check Supabase or Backblaze connectivity.

## Module boundaries

- Import `server-only` in each server entry point to prevent accidental use in a Client Component.
- Export services through explicit package exports instead of reaching into internal paths.
- Keep HTTP request/response handling in the frontend's `app/api/` routes.
- Add authentication and ownership checks alongside each protected feature.
- Read runtime environment settings from the Next.js application environment; this package has no separate `.env` file or server process.

Upcoming modules follow `PROJECT_PLAN.md`: authentication, administration, notebook documents, synchronization, file storage, imports, and database access.
