# MyNotes — Full-stack Next.js application

One application, one `package.json`, one environment file, and one Vercel deployment. Next.js serves the interface and backend API routes together.

## Current step: desktop-style cloud drawing and Mac import

Implemented:

- Next.js App Router and TypeScript frontend.
- Supabase email/password sign-in, Google OAuth callbacks, password setup/recovery, session refresh, and logout.
- Server-protected admin APIs, invited-user access checks, and private notebook APIs.
- A local `admin:invite` command to send the initial administrator setup email.
- Responsive landing, authentication, notebook, editor, and admin page layouts.
- Admin invitation/resend/revocation controls and live account counts.
- Persistent notebook sidebar with search, creation, rename, deletion, and native-style navigation.
- Continuous multi-page canvas with a movable drawing palette, pen/pencil/highlighter, shapes, whole-stroke erasing, lasso selection/transforms, undo/redo, text, paper settings, zoom/pan/fit, and PDF export.
- Import existing Mac notebook exports or raw `.drawing.json` ink, preserving native path geometry and styles.
- IndexedDB recovery drafts, revision-conflict copies, and versioned JSON backups/imports.
- Shared workspace navigation and a collapsed mobile menu.
- Server-only application services under `src/server/`.
- Versioned application-liveness endpoint at `/api/v1/health`.
- TypeScript settings, ESLint, npm scripts, and a lockfile.
- Notebook SQL migration with default-deny RLS and server-only table access.

**Start here:** follow [`ADMIN_SETUP.md`](ADMIN_SETUP.md) to configure the deployed domain, send the initial admin email, choose a password, and sign in.

Authentication, user management, and notebook persistence use the configured Supabase project. Apply `supabase/migrations/001_notebooks.sql` and configure `SUPABASE_SECRET_KEY` in the deployed server environment. The administrator and verified users with an admin-issued app-metadata grant can open their own libraries. `/preview/admin` redirects to `/admin`.

### Pages

| Route | Purpose |
| --- | --- |
| `/` | Product landing page and workspace links |
| `/login` | Invited account email/password and Google sign-in |
| `/invite` | Invitation instructions; authorized users continue to password setup |
| `/forgot-password` | Invited account password-reset email request |
| `/reset-password` | Protected password setup/change form |
| `/notebooks` | Private notebook sidebar, search/sort, creation/deletion, and Mac/JSON import |
| `/notebooks/<uuid>` | Continuous drawing editor with cloud autosave, recovery drafts, and PDF/JSON export |
| `/admin` | Server-protected account dashboard and invitation management |
| `/preview/admin` | Redirect to `/admin` |
| `/auth/callback` | OAuth PKCE and invitation/recovery callback |
| `/auth/complete` | Exchanges default email-link fragments for HTTP-only session cookies |
| `/setup` | Development progress and API health link |

The web notebook layout follows the native Mac app. Drawings are editable and cloud-backed. Mac exports preserve point paths, full-precision styles, IDs, paper settings, text, and bounded inline images. Transfer instructions and format details are in [`NOTEBOOK_TRANSFER.md`](NOTEBOOK_TRANSFER.md). Native cloud decoding and automatic Mac synchronization remain in [`DESKTOP_AUTH_PLAN.md`](../DESKTOP_AUTH_PLAN.md).

## Local development

Use **Node.js 24 LTS** (see `.nvmrc`). Node.js 22.13+ is also supported. Node.js 20 is no longer supported by the Supabase SDK used for authentication.

Run these commands from the `web-app/` directory:

```sh
npm ci
npm run dev
```

Open <http://localhost:3000>.

From the repository root, use `npm --prefix web-app run dev`. All web dependencies are installed in `web-app/` using its single lockfile.

### Checks and production build

```sh
npm run check
npm run test:database
npm run build
npm run start
```

- `check`: ESLint plus type checking of pages, API routes, server services, and browser tests.
- `test:database`: executes the actual migration in embedded PostgreSQL (PGlite), checking derived metadata, permissions/RLS, and stale revision handling.
- `build`: production Next.js build including all pages and backend API routes.
- `start`: serve the completed production build.

### Browser checks

```sh
npx playwright install chromium
npm run build
npm run test:e2e
```

Playwright starts the production application on port 3101 and a stateful local Supabase-shaped HTTP fixture on port 54329. Tests cover authentication, invitations, ownership, revision conflicts, page/drawing persistence, erasing/history, lasso movement, PDF generation, native import compatibility/deduplication, draft recovery, JSON backups, and mobile layout. Tests run serially because they share the fixture. CI runs these plus the database checks. Screenshots and failure traces are written to ignored `test-results/` paths.

For the focused authentication suite only, use `npm run test:auth` after building. Tests use a separate local mock provider on port 54329 and fake credentials; they do not send real emails or use your hosted Supabase project. Run the full regression suite only when the changes warrant it.

### API smoke check

With the application running:

```sh
curl http://localhost:3000/api/v1/health
```

Expected response:

```json
{"status":"ok","service":"mynotes-api","apiVersion":"v1","stage":"foundation"}
```

This checks application liveness, not external service availability.

## Environment setup

For a new checkout, copy `.env.example` to `.env.local` inside `web-app/` and fill in the relevant values. The existing local environment file was moved to this location during consolidation. Next.js loads it for the whole application. Local environment files are ignored by Git.

| Setting | Purpose | Used in step |
| --- | --- | --- |
| `APP_URL` | Application origin and authentication redirects | Authentication |
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase project URL | Authentication |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Public Supabase client key | Authentication |
| `SUPABASE_SECRET_KEY` | Server-only Supabase secret key or legacy service-role key | Admin setup, user management, recovery eligibility, notebooks |
| `ADMIN_EMAIL` | Initial administrator email | Admin bootstrap |
| `B2_ENDPOINT` | B2 S3-compatible endpoint | File storage |
| `B2_REGION` | B2 bucket region | File storage |
| `B2_BUCKET_NAME` | Private bucket name | File storage |
| `B2_APPLICATION_KEY_ID` | Server-only B2 application-key ID | File storage |
| `B2_APPLICATION_KEY` | Server-only B2 application key | File storage |

The account/notebook increment requires the Supabase URL, publishable key, server secret, `ADMIN_EMAIL`, and `APP_URL`, plus the SQL migration. B2 configuration is reserved for the file-storage integration.

### Admin password and invitation email

`ADMIN_EMAIL` identifies the administrator. The login password will be set through Supabase authentication, rather than stored in a project environment variable.

If your email provider requires an app password, use it as the SMTP password in **Supabase Auth → SMTP Settings**. Configure the SMTP host, port, sender, and credentials there. Google sign-in uses its own OAuth configuration in Supabase.

Configure SMTP before sending the initial admin invitation; Supabase's default sender restricts delivery to project-team addresses. Deployment and invitation commands are in [`ADMIN_SETUP.md`](ADMIN_SETUP.md).

## Application layout

```text
web-app/
├── package.json             # All web dependencies and commands
├── package-lock.json
├── .env.example
├── .env.local               # Local configuration, ignored by Git
├── next.config.ts
├── tsconfig.json
├── eslint.config.mjs
├── vercel.json
├── tests/
└── src/
    ├── app/                 # Pages and layouts
    │   └── api/             # Backend HTTP endpoints
    ├── components/
    ├── features/
    └── server/              # Server-only business logic
```

API routes import business logic through `@/server/`. Server entry points use `server-only`, so importing them into client code is a build error. Next.js bundles the routes and their server dependencies in the same build as the pages.

## Vercel configuration

Use one Vercel project for the full-stack application:

1. Import the repository as a Next.js project.
2. Set **Root Directory** to `web-app`.
3. Disable **Include source files outside of the Root Directory in the Build Step**; all web source code is inside the application root.
4. Use **Node.js 24.x**.
5. `vercel.json` sets **Install Command** to `npm ci` and **Build Command** to `npm run build`. Update any old dashboard overrides to match these values. Keep the default Next.js output directory.
6. Add environment variables through Vercel's project settings when the corresponding integration is implemented.

Vercel deploys the frontend and API routes together. The initial personal, non-commercial deployment can use Hobby within its limits.

### Resolve the invalid Serverless Function name error

The previous directory name contained a space, which was included in Vercel's generated `___next_launcher.cjs` function path. Vercel rejects function names containing spaces.

The application now lives entirely in `web-app/`, with standard Next.js configuration and no sibling-package file tracing. After pushing the consolidation changes:

1. Update the existing Vercel project's root and build settings as listed above.
2. Deploy the **latest commit containing `web-app/`**, rather than rebuilding a commit with the old structure.
3. For this first corrected deploy, turn off **Use existing Build Cache**.
4. Verify both `/login` and `/api/v1/health` on the deployment URL. The health endpoint exercises the server logic within the same deployed application.

### Connect the application domain

1. Add `mynotes.gnyanarushi.tech` under **Vercel → Project → Settings → Domains**.
2. Add the DNS record Vercel displays at the DNS provider for `gnyanarushi.tech`. For this subdomain the record name is normally `mynotes`; copy the CNAME target from Vercel rather than guessing it.
3. Wait for Vercel to verify the domain and provision HTTPS.
4. Check the landing, login, private notebook library, and protected admin pages on the domain.

For authentication, configure:

| Setting | Production value |
| --- | --- |
| Application `APP_URL` | `https://mynotes.gnyanarushi.tech` |
| Supabase Site URL | `https://mynotes.gnyanarushi.tech` |
| Supabase allowed app redirects | `https://mynotes.gnyanarushi.tech/auth/callback` and `https://mynotes.gnyanarushi.tech/auth/callback?next=%2Freset-password` |
| Google authorized redirect URI | The Supabase-provided `https://<project-ref>.supabase.co/auth/v1/callback` |

The callback validates the Supabase identity before granting administrator access. See [`ADMIN_SETUP.md`](ADMIN_SETUP.md) for password setup and Google provider configuration.

## Notebook API and current limits

- `GET /api/notebooks?search=...`: owned notebook summaries; search includes titles and page text.
- `POST /api/notebooks`: `{ id, document, mutationId }`, all IDs UUIDs; creates a notebook at revision 1.
- `POST /api/notebooks/import`: `{ value, filename, id, mutationId }`; validates a web backup/Mac export and stores a private notebook. Native imports are deduplicated by account, source ID, and converted content.
- `GET /api/notebooks/<id>`: owned document with `revision`, `mutation_id`, and timestamps.
- `PUT /api/notebooks/<id>`: `{ id, document, mutationId, revision }`; atomically updates only the supplied base revision. Stale edits return 409.
- `DELETE /api/notebooks/<id>`: `{ revision }`; rejects stale deletion attempts.
- `GET /api/admin/users` and `POST /api/admin/users`: admin-only account listing and `{ email, action: "invite" | "resend" | "revoke" }` operations.

Mutations require same-origin JSON requests and a verified HTTP-only session. Notebook bodies are limited to 3 MB and 300 pages; JSON imports to 2.9 MB. The full document is saved as one record. Immediate retries of the latest mutation are idempotent, including simultaneous create requests. Deletions are currently permanent, and conflicts create an explicitly requested **whole-notebook copy**.

Recovery drafts are keyed by account and notebook in IndexedDB. Reopening a notebook restores an interrupted save; reconnecting or **Save now** retries it. Successful cloud saves remove their draft. Sign-out clears credentials and hides the library while retaining unsaved drafts for the same account's next sign-in. This is web recovery, not full offline operation or the Mac sign-out protocol.

## Next implementation step

Apply the migration, deploy, and verify email delivery/Google identity linking on the configured Supabase project. Next, implement native bearer admission, desktop sign-in and account storage from [`DESKTOP_AUTH_PLAN.md`](../DESKTOP_AUTH_PLAN.md), finish the reverse drawing conversion, and introduce the change feed, durable operation ledger, deletion records, and per-page conflict protocol in [`PROJECT_PLAN.md`](../PROJECT_PLAN.md).
