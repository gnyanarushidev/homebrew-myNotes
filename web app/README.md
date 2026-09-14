# MyNotes web workspace

## Current step: frontend page previews

Implemented:

- Next.js App Router and TypeScript frontend.
- Responsive landing, authentication, notebook, editor, and admin page layouts.
- Preview-only interactions: form validation, notebook search and creation, grid/list views, paper selection, zoom, page navigation, and sample invitations.
- Shared workspace navigation and a collapsed mobile menu.
- Server-only backend workspace package.
- Versioned application-liveness endpoint at `/api/v1/health`.
- Shared TypeScript settings, ESLint, npm workspace scripts, and a lockfile.
- Environment template for upcoming authentication and storage integrations.

The workspace starts without Supabase, Backblaze, or email credentials. All displayed accounts and notebooks are fictional. Preview changes stay in React memory and reset on reload or when leaving the workspace routes. Forms do not submit credentials, create real accounts, or send emails.

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

Use **Node.js 24 LTS** (see `.nvmrc`). The workspace also supports Node.js 20.19+ and 22.13+.

Run these commands from the `web app/` directory:

```sh
npm ci
npm run dev
```

Open <http://localhost:3000>.

From the repository root, use `npm --prefix "web app" run dev`. Install dependencies at the web workspace root so both packages share the lockfile.

### Checks and production build

```sh
npm run check
npm run build
npm run start
```

- `check`: ESLint plus type checking of both packages.
- `build`: production Next.js build including the backend package.
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

When ready, copy `frontend/.env.example` to `frontend/.env.local` and fill in the relevant values. Next.js loads environment files from `frontend/`, even when started through the root workspace scripts. Local environment files are ignored by Git.

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

## Workspace layout

```text
web app/
├── package.json             # npm workspaces and shared commands
├── package-lock.json
├── tsconfig.base.json
├── eslint.config.mjs
├── frontend/                # @mynotes/frontend
│   ├── .env.example
│   ├── next.config.ts
│   └── src/
│       ├── app/             # Pages, layouts, and API routes
│       └── features/        # Feature UI
└── backend/                 # @mynotes/backend
    └── src/                 # Server-only application services
```

`frontend/next.config.ts` configures package transpilation and file tracing to include `backend/`. Backend entry points use `server-only`, so importing them into client code is a build error.

## Vercel configuration

When deploying the frontend preview:

1. Import the repository as a Next.js project.
2. Set **Root Directory** to `web app/frontend`.
3. Enable **Include source files outside of the Root Directory in the Build Step** so the sibling backend package and workspace configuration are available.
4. Use **Node.js 24.x**.
5. `frontend/vercel.json` sets **Install Command** to `npm --prefix .. ci` and **Build Command** to `npm run build`. Keep the default Next.js output directory.
6. Add environment variables through Vercel's project settings when the corresponding integration is implemented.

Vercel deploys the frontend and API routes together. The initial personal, non-commercial deployment can use Hobby within its limits.

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
