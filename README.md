# MyNotes

MyNotes is becoming a shared web and Mac notebook application with private accounts and offline desktop synchronization. The native application is available today; the web workspace is being built in small, verifiable steps.

## Repository

| Path | Purpose |
| --- | --- |
| [`desktop app/`](desktop%20app/) | Native SwiftUI, AppKit, and PencilKit project, resources, and regression harnesses |
| [`web app/frontend/`](web%20app/frontend/) | Next.js interface and HTTP API routes |
| [`web app/backend/`](web%20app/backend/) | Server-only TypeScript services imported by the Next.js app |
| [`Casks/`](Casks/) | Homebrew distribution metadata |
| [`PROJECT_PLAN.md`](PROJECT_PLAN.md) | Agreed requirements and implementation phases |

## Current step: frontend page previews

The web workspace now includes landing, sign-in, invitation, password-recovery, notebook-library, editor, and admin page previews. Search, preview notebook creation, paper/zoom controls, and sample invitations are interactive. All preview data is fictional and session-local.

The next step is deploying the pages to Vercel and connecting `mynotes.gnyanarushi.tech`, followed by Supabase authentication and the admin invitation flow. Drawing, cloud storage, and desktop synchronization follow the sequence in the project plan.

## Run the web application

Use Node.js 24 LTS for new development environments and deployment. The workspace also supports Node.js 20.19+ and 22.13+.

From the repository root:

```sh
npm --prefix "web app" ci
npm --prefix "web app" run dev
```

Open <http://localhost:3000>. The health endpoint is <http://localhost:3000/api/v1/health>.

Try `/login`, `/invite`, `/notebooks`, `/notebooks/everyday-ideas`, and `/admin`. The authentication screens are previews; the admin page uses sample accounts only.

```sh
npm --prefix "web app" run check
npm --prefix "web app" run build
npm --prefix "web app" run start
```

See [`web app/README.md`](web%20app/README.md) for environment configuration, workspace boundaries, and Vercel settings.

## Run the Mac application

```sh
zsh "desktop app/run-macos.sh"
```

Or open `desktop app/MyNotes.xcodeproj` in Xcode and select the **MyNotes macOS** scheme. Native build, usage, Homebrew, and test details are in [`desktop app/README.md`](desktop%20app/README.md).
