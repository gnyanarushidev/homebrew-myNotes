# MyNotes server logic

Server-only TypeScript services live inside the Next.js application and are imported by routes in `src/app/api/`. One package, build, environment file, and Vercel deployment serve the entire web application.

## Current entry point

- `@/server/health`: application liveness, exposed at `/api/v1/health`.

The health response confirms that the application is running. It does not check Supabase or Backblaze connectivity.

## Module boundaries

- Import `server-only` in each server entry point to prevent accidental use in a Client Component.
- Import server services through the `@/server/` path alias.
- Keep HTTP request/response handling in `src/app/api/` routes.
- Add authentication and ownership checks alongside each protected feature.
- Read runtime environment settings from the Next.js application environment at `web-app/.env.local` locally and Vercel project settings when deployed.

Upcoming modules follow `PROJECT_PLAN.md`: authentication, administration, notebook documents, synchronization, file storage, imports, and database access.
