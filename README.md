# MyNotes

MyNotes is becoming a shared web and Mac notebook application with private accounts and offline desktop synchronization. The native application is available today; the full-stack Next.js application is being built in small, verifiable steps.

## Repository

| Path | Purpose |
| --- | --- |
| [`desktop app/`](desktop%20app/) | Native SwiftUI, AppKit, and PencilKit project, resources, and regression harnesses |
| [`web-app/`](web-app/) | One Next.js application: pages, API routes, server logic, and environment configuration |
| [`Casks/`](Casks/) | Homebrew distribution metadata |
| [`PROJECT_PLAN.md`](PROJECT_PLAN.md) | Agreed requirements and implementation phases |

## Current step: administrator authentication

The web application now includes Supabase administrator sign-in, password setup/recovery, Google OAuth support, a protected admin dashboard, session refresh, and logout. Notebook and user-management interface previews remain available with fictional, session-local data.

Follow [`web-app/ADMIN_SETUP.md`](web-app/ADMIN_SETUP.md) to redeploy, send the configured administrator a setup email, and sign in at `mynotes.gnyanarushi.tech/login`. General user invitations, drawing, cloud storage, and desktop synchronization follow the project plan.

## Run the web application

Use Node.js 24 LTS for development and deployment. The application also supports Node.js 22.13+; its Supabase SDK requires Node.js 22 or later.

From the repository root:

```sh
npm --prefix web-app ci
npm --prefix web-app run dev
```

Open <http://localhost:3000>. The health endpoint is <http://localhost:3000/api/v1/health>.

Try `/login` and the protected `/admin` dashboard. Notebook previews are at `/notebooks`; the fictional user-management interface is at `/preview/admin`.

```sh
npm --prefix web-app run check
npm --prefix web-app run build
npm --prefix web-app run start
```

See [`web-app/README.md`](web-app/README.md) for environment configuration and Vercel settings.

## Deploy the whole web application

Use one Vercel project with **Root Directory `web-app`**, **Framework Next.js**, and **Node.js 24.x**. The included `vercel.json` uses `npm ci` and `npm run build`. Pages and API routes are deployed together on the same domain.

For an existing Vercel project, update its previous root directory, disable **Include source files outside of the Root Directory**, and redeploy the latest commit with the build cache disabled. The folder name `web-app` has no spaces, so generated function names meet Vercel's naming requirements.

Local configuration lives in `web-app/.env.local`. Hosted configuration goes in the same Vercel project's environment settings.

## Run the Mac application

```sh
zsh "desktop app/run-macos.sh"
```

Or open `desktop app/MyNotes.xcodeproj` in Xcode and select the **MyNotes macOS** scheme. Native build, usage, Homebrew, and test details are in [`desktop app/README.md`](desktop%20app/README.md).
