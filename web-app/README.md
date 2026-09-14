# MyNotes — Full-stack Next.js application

One application, one `package.json`, one environment file, and one Vercel deployment. Next.js serves the interface and backend API routes together.

## Current step: frontend page previews

Implemented:

- Next.js App Router and TypeScript frontend.
- Responsive landing, authentication, notebook, editor, and admin page layouts.
- Preview-only interactions: form validation, notebook search and creation, grid/list views, paper selection, zoom, page navigation, and sample invitations.
- Shared workspace navigation and a collapsed mobile menu.
- Server-only application services under `src/server/`.
- Versioned application-liveness endpoint at `/api/v1/health`.
- TypeScript settings, ESLint, npm scripts, and a lockfile.
- Environment template for upcoming authentication and storage integrations.

The current preview starts without Supabase, Backblaze, or email credentials. All displayed accounts and notebooks are fictional. Preview changes stay in React memory and reset on reload or when leaving the workspace routes. Forms do not submit credentials, create real accounts, or send emails.

### Pages

| Route | Purpose |
| --- | --- |
| `/` | Product landing page and links into the preview |
| `/login` | Email/password and Google sign-in layout |
| `/invite` | Invitation acceptance and password setup layout |
| `/forgot-password` | Password-recovery form layout |
| `/reset-password` | New-password form with confirmation validation |
| `/notebooks` | Sample library, search, sort, grid/list views, and preview notebook creation |
| `/notebooks/everyday-ideas` | Sample editor with paper, zoom, and page controls |
| `/admin` | Fictional user counts, invitation list, and preview invite/revoke actions |
| `/auth/callback` | Clearly labeled placeholder for the upcoming authentication callback |
| `/setup` | Development progress and API health link |

The editor displays sample page artwork; drawing tools and PDF export are visibly disabled until the editor implementation. The admin page is a public UI preview backed only by fixtures. Real account data will be introduced together with server-side access controls.

## Local development

Use **Node.js 24 LTS** (see `.nvmrc`). The application also supports Node.js 20.19+ and 22.13+.

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
| `SUPABASE_SECRET_KEY` | Server-only Supabase secret key or legacy service-role key | Admin invitations |
| `ADMIN_EMAIL` | Initial administrator email | Admin bootstrap |
| `B2_ENDPOINT` | B2 S3-compatible endpoint | File storage |
| `B2_REGION` | B2 bucket region | File storage |
| `B2_BUCKET_NAME` | Private bucket name | File storage |
| `B2_APPLICATION_KEY_ID` | Server-only B2 application-key ID | File storage |
| `B2_APPLICATION_KEY` | Server-only B2 application key | File storage |

These are reserved configuration names; adding credentials alone does not enable the future integrations. Service initialization and validation will be added with each integration.

### Admin password and invitation email

`ADMIN_EMAIL` identifies the administrator. The login password will be set through Supabase authentication, rather than stored in a project environment variable.

If your email provider requires an app password, use it as the SMTP password in **Supabase Auth → SMTP Settings**. Configure the SMTP host, port, sender, and credentials there. Google sign-in uses its own OAuth configuration in Supabase.

For the next step, prepare the Supabase project settings and admin email. Configure SMTP before testing invitations to external recipients; Supabase's default sender restricts delivery to project-team addresses.

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

After the authentication integration is implemented, configure:

| Setting | Production value |
| --- | --- |
| Application `APP_URL` | `https://mynotes.gnyanarushi.tech` |
| Supabase Site URL | `https://mynotes.gnyanarushi.tech` |
| Supabase allowed app redirect | `https://mynotes.gnyanarushi.tech/auth/callback` |
| Google authorized redirect URI | The Supabase-provided `https://<project-ref>.supabase.co/auth/v1/callback` |

The application callback is a preview placeholder today; it does not exchange authorization codes or accept invitations yet.

## Next implementation step

Deploy these pages and connect the custom domain first. Then connect Supabase, define protected user/invitation data, and implement verified admin bootstrap plus email/password and Google sign-in. Continue with the shared document prototype and cloud features according to [`PROJECT_PLAN.md`](../PROJECT_PLAN.md).
