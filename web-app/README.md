# MyNotes — Full-stack Next.js application

One application, one `package.json`, one environment file, and one Vercel deployment. Next.js serves the interface and backend API routes together.

## Current step: administrator authentication

Implemented:

- Next.js App Router and TypeScript frontend.
- Supabase email/password sign-in, Google OAuth callbacks, password setup/recovery, session refresh, and logout.
- Server-protected `/admin` and authentication APIs, restricted to the verified `ADMIN_EMAIL` identity.
- A local `admin:invite` command to send the initial administrator setup email.
- Responsive landing, authentication, notebook, editor, and admin page layouts.
- Preview-only notebook search and creation, grid/list views, paper selection, zoom, page navigation, and sample invitation management.
- Shared workspace navigation and a collapsed mobile menu.
- Server-only application services under `src/server/`.
- Versioned application-liveness endpoint at `/api/v1/health`.
- TypeScript settings, ESLint, npm scripts, and a lockfile.
- Environment template for upcoming authentication and storage integrations.

**Start here:** follow [`ADMIN_SETUP.md`](ADMIN_SETUP.md) to configure the deployed domain, send the initial admin email, choose a password, and sign in.

Authentication now uses the configured Supabase project. The notebook library and `/preview/admin` remain fictional interface previews; their changes stay in React memory. Only the verified configured administrator receives access to the real `/admin` dashboard in this milestone. General user invitations and cloud notebooks follow in subsequent steps.

### Pages

| Route | Purpose |
| --- | --- |
| `/` | Product landing page and links into the preview |
| `/login` | Administrator email/password and Google sign-in |
| `/invite` | Invitation instructions; verified admins continue to password setup |
| `/forgot-password` | Administrator password-reset email request |
| `/reset-password` | Protected password setup/change form |
| `/notebooks` | Sample library, search, sort, grid/list views, and preview notebook creation |
| `/notebooks/everyday-ideas` | Sample editor with paper, zoom, and page controls |
| `/admin` | Server-protected administrator account dashboard |
| `/preview/admin` | Fictional user counts and invitation-management UI |
| `/auth/callback` | OAuth PKCE and invitation/recovery callback |
| `/auth/complete` | Exchanges default email-link fragments for HTTP-only session cookies |
| `/setup` | Development progress and API health link |

The editor displays sample page artwork; drawing tools and PDF export are visibly disabled until the editor implementation. The sample administration UI is explicitly separate from the protected account dashboard.

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
npm run build
npm run start
```

- `check`: ESLint plus type checking of pages, API routes, server services, and browser tests.
- `build`: production Next.js build including all pages and backend API routes.
- `start`: serve the completed production build.

### Browser checks

```sh
npx playwright install chromium
npm run build
npm run test:e2e
```

Playwright starts the production application on port 3101 and checks routes, authentication form behavior, notebook creation/navigation, sample invitations, and mobile layout. CI runs the same checks. Screenshots and failure traces are written to ignored `test-results/` paths.

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

## Environment setup for the next steps

For a new checkout, copy `.env.example` to `.env.local` inside `web-app/` and fill in the relevant values. The existing local environment file was moved to this location during consolidation. Next.js loads it for the whole application. Local environment files are ignored by Git.

| Setting | Purpose | Used in step |
| --- | --- | --- |
| `APP_URL` | Application origin and authentication redirects | Authentication |
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase project URL | Authentication |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Public Supabase client key | Authentication |
| `SUPABASE_SECRET_KEY` | Supabase secret key or legacy service-role key used by the local setup command | Initial admin invitation |
| `ADMIN_EMAIL` | Initial administrator email | Admin bootstrap |
| `B2_ENDPOINT` | B2 S3-compatible endpoint | File storage |
| `B2_REGION` | B2 bucket region | File storage |
| `B2_BUCKET_NAME` | Private bucket name | File storage |
| `B2_APPLICATION_KEY_ID` | Server-only B2 application-key ID | File storage |
| `B2_APPLICATION_KEY` | Server-only B2 application key | File storage |

Authentication requires the Supabase URL, publishable key, `ADMIN_EMAIL`, and `APP_URL`. B2 configuration is reserved for the storage integration. The admin invitation command additionally requires `SUPABASE_SECRET_KEY`.

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
4. Check the landing, login, notebook preview, and admin preview pages on the domain.

For authentication, configure:

| Setting | Production value |
| --- | --- |
| Application `APP_URL` | `https://mynotes.gnyanarushi.tech` |
| Supabase Site URL | `https://mynotes.gnyanarushi.tech` |
| Supabase allowed app redirects | `https://mynotes.gnyanarushi.tech/auth/callback` and `https://mynotes.gnyanarushi.tech/auth/callback?next=%2Freset-password` |
| Google authorized redirect URI | The Supabase-provided `https://<project-ref>.supabase.co/auth/v1/callback` |

The callback validates the Supabase identity before granting administrator access. See [`ADMIN_SETUP.md`](ADMIN_SETUP.md) for password setup and Google provider configuration.

## Next implementation step

Deploy the authentication update and activate the administrator. Next, define protected user/invitation data for general user onboarding, then continue with the shared document prototype and cloud features in [`PROJECT_PLAN.md`](../PROJECT_PLAN.md).
