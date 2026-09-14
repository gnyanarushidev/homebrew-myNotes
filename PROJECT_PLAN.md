# MyNotes — Project Requirements and Implementation Plan

**Status:** Repository scaffold and basic frontend page previews implemented. Deployment/domain setup precedes authentication integration.
**Initial audience:** Personal, non-commercial use by invited users.
**Platforms:** Web application and native macOS application.

### Implementation progress

The first increment delivered:

- Native sources, resources, Xcode project, and regression harnesses under `desktop app/`.
- A Next.js application with both interface pages and server-side services, now consolidated under `web-app/`.
- A responsive foundation page and `/api/v1/health` liveness endpoint.
- Shared TypeScript configuration, linting, a dependency lockfile, and web CI checks.
- Environment templates and local/Vercel setup instructions.

Verification completed: web linting and type checking, production build, live homepage/API smoke checks, native macOS build, and all eight existing selection regressions.

The second increment adds landing, sign-in, invitation, password recovery/reset, notebook library, editor, admin, and authentication-callback preview pages. Preview notebook and invitation interactions use fictional in-memory data. The editor exposes paper, zoom, and page controls, with drawing capture and PDF export scheduled for the editor milestone.

Second-increment verification completed: linting, TypeScript checks, production build, and six browser tests covering routes, form behavior, notebook interactions, sample invitations, and mobile layout. Browser tests also confirm that the authentication preview does not issue external requests.

The web code has been consolidated into one Next.js application under `web-app/`: one package, one local environment file, one build, and one Vercel deployment. Pages live in `src/app/`, backend HTTP endpoints in `src/app/api/`, and server-only services in `src/server/`. The space-free application directory resolves the invalid generated function-name issue encountered during Vercel deployment.

Consolidation verification completed locally: clean dependency installation, linting, TypeScript checks, production build, all six browser tests including the live backend health endpoint, and build-trace checks for the new application root. The existing Vercel project must be updated to Root Directory `web-app` before redeploying the latest commit.

The immediate next step is to deploy this full-stack application to Vercel and connect `mynotes.gnyanarushi.tech`, then implement Supabase authentication and the admin invitation flow. See [`web-app/README.md`](web-app/README.md) for deployment and callback settings. The shared-document prototype remains an early prerequisite for implementing notebook content and synchronization.

The phase table below remains the full roadmap; its shared-document, authentication, and synchronization deliverables will be completed in later increments.

## 1. Project goal

Provide a private notebook application where invited users can:

- Access the same account and notebooks through the web and Mac apps.
- Draw and manage multi-page notebooks.
- Download their notebooks to the Mac for offline use.
- Continue editing without an internet connection.
- Synchronize local changes and receive cloud changes when connectivity returns.

Each user's notebooks belong to their account.

### Confirmed first-release decisions

- Next.js full-stack, with Supabase Auth/Postgres and Backblaze B2.
- One repository containing `desktop app/` and `web-app/`.
- One full-stack Next.js application inside `web-app/`, with pages, API routes, and server logic deployed together.
- Desktop-first, drawing-first web experience.
- Private notebooks and admin-managed invitations.
- Email/password and Google sign-in on both web and Mac.
- Initial admin identified through a server-only `ADMIN_EMAIL` setting.
- Import existing notebooks from the Mac app.
- Automatically download all of the signed-in user's notebooks for offline Mac use.
- Bidirectional synchronization between web, cloud, and Mac.
- Preserve both versions when cloud and offline edits conflict.
- Remove local account data after pending changes are synchronized on sign-out.
- Vercel Hobby for the initial personal deployment, within its eligibility and usage limits.

## 2. Technology stack

| Component | Technology |
| --- | --- |
| Web frontend | Next.js + TypeScript |
| Shared backend API | Next.js Route Handlers and server-only TypeScript services |
| Native Mac app | Existing SwiftUI/AppKit application |
| Authentication | Supabase Auth |
| Cloud database | Supabase Postgres |
| Cloud file storage | Backblaze B2 |
| Mac local persistence | Account-specific SwiftData storage and local drawing/asset storage |
| Web deployment | Vercel |
| Browser drawing | React Konva, validated through an early prototype |
| Authentication emails | Custom SMTP connected to Supabase; provider to confirm |

Vercel Hobby is the initial hosting choice for personal, non-commercial use within its limits. Supabase, Backblaze, and email delivery have separate usage allowances and pricing. Commercial expansion requires reassessing service plans and capacity.

Spring Boot was evaluated and supports deployment on Render through Docker. Next.js full-stack was selected to keep one implementation language and one web application deployment.

### System overview

```text
Web application                         Native Mac application
    |                                       |
    +---------- Supabase Auth --------------+
    |                                       |
    |                              Per-account local storage
    |                              and durable sync queue
    |                                       |
    +--------- Shared Next.js API -----------+
                       |
                       +-- Supabase Postgres
                       |   Accounts, notebooks, documents, revisions
                       |
                       +-- Backblaze B2
                           Files and authorized signed URLs
```

Both clients use the shared API for notebook and synchronization operations. File transfers use object-specific signed URLs issued after ownership checks.

## 3. Repository organization

Application structure, with additional server modules introduced in their implementation phases:

```text
MyNotes/
├── .git/
├── .github/
├── README.md
├── PROJECT_PLAN.md
│
├── desktop app/
│   ├── App/
│   ├── Core/
│   ├── Drawing/
│   ├── Features/
│   ├── Resources/
│   ├── Tests/
│   ├── MyNotes.xcodeproj/
│   └── run-macos.sh
│
└── web-app/
    ├── package.json
    ├── package-lock.json
    ├── .env.local
    ├── next.config.ts
    ├── vercel.json
    └── src/
        ├── app/
        │   └── api/
        ├── components/
        ├── features/
        └── server/
            ├── auth/
            ├── admin/
            ├── notebooks/
            ├── sync/
            ├── storage/
            ├── imports/
            └── database/
```

The `src/server/` folder contains server-only services used by Next.js API routes. The entire `web-app/` directory is a single application with one package manifest and build. Set Vercel's Root Directory to `web-app`.

Reorganization includes updating build scripts, CI paths, documentation, and environment-file locations. The deployed application path uses a hyphen so generated Vercel function names contain no spaces. Shell commands must quote native-app paths containing spaces.

## 4. Accounts, administration, and invitations

### Administrator

- Initial administrator configured using server-only `ADMIN_EMAIL`.
- Setup provisions the admin account and associates it with a verified Supabase user identity.
- Web admin panel displays:
  - Total onboarded users.
  - Pending invitations.
  - User list and invitation/acceptance dates.
- Admin can send, resend, and revoke pending invitations.
- Admin can also use their own notebooks.

Administrative actions require backend authorization. Role assignments are protected application data, not user-editable profile metadata. Supabase administrative credentials are available only to authorized server-side operations.

### Invited users

1. Admin enters the user's email address.
2. The user receives an invitation email.
3. The user opens the invitation and:
   - Sets a password for the invited email; or
   - Continues with Google using that email.
4. The application verifies the invitation and identity.
5. The user receives access to their private notebook library.

The same identity and notebooks are used across both login methods and both applications.

- Application access requires an accepted invitation or the configured administrator identity.
- Invitation restrictions must apply to email/password and Google authentication.
- Expired, revoked, duplicate, and already-accepted invitations receive clear handling.
- Account features include password reset, session management, and sign-out.
- Notebook ownership is enforced through backend checks and Supabase row-level security.

### Email delivery

Custom SMTP is required to invite ordinary users. Supabase's default email service restricts delivery to project-team addresses.

Recommended setup: Resend connected to Supabase SMTP, using a verified sending domain. The provider and domain remain setup decisions.

## 5. Desktop authentication

- First-time sign-in on a Mac requires internet access.
- The notebook library opens only after successful authentication and application-access validation.
- Mac supports email/password and Google sign-in through Supabase.
- Google authentication uses a browser-based authentication session and a registered application callback.
- Session credentials are stored in macOS Keychain.
- Web and Mac have separate device sessions associated with the same Supabase user ID.
- Backend APIs validate the Mac's access token and authorize every operation.

### Previously authenticated offline access

A user who remains signed in can reopen the Mac app and use downloaded notebooks offline, including after an app restart.

Offline local access is separate from cloud authorization:

- An expired cloud access token does not discard local work.
- Reconnection refreshes the session before cloud requests.
- If reauthentication is required, pending edits remain recoverable.
- Remote access changes can be discovered only after reconnecting.
- An explicitly signed-out account requires online sign-in before its retained work can be reopened.

## 6. Per-user local storage

Each account has its own local:

- Notebook database.
- Drawing documents.
- Downloaded assets.
- Pending synchronization queue.
- Synchronization cursor and revision information.

Storage is partitioned using the immutable Supabase user ID.

Account changes must close the previous account's store and cancel its active sync tasks before opening another account.

Late responses from a previous session must never populate the next user's library.

## 7. Downloads and offline notebook features

After online sign-in:

- Load the user's notebook list.
- Download all notebooks, pages, drawing documents, and required assets.
- Display download progress and per-notebook offline readiness.
- Resume interrupted downloads.

A notebook is marked **Available offline** only after its required content is stored successfully.

Downloaded notebooks support offline:

- Reading and drawing.
- Notebook creation and renaming.
- Page creation and deletion.
- Paper-style changes.
- Selection and transformations.
- Undo/redo.
- Local search.
- PDF export.

Every committed edit is saved locally first and recorded for synchronization.

## 8. Synchronization requirements

Synchronization is **bidirectional**:

```text
Mac local edits → shared backend → cloud
Cloud/web edits → shared backend → Mac local storage
```

### Triggers

- Successful sign-in.
- Application launch or return to the foreground.
- Local edits, after batching.
- Connectivity recovery.
- Periodic checks while the app is active.
- A manual "Sync now" action.

If the app is closed, synchronization resumes on its next launch.

### Reliability

- Maintain a durable pending-change queue across crashes and restarts.
- Persist each committed local change together with its pending-sync entry. If drawings remain separate files, use atomic file writes and transactional references so interrupted saves remain recoverable.
- Assign unique operation IDs so retries do not duplicate changes.
- Include the revision on which each edit was based.
- Mark an operation synchronized only after server acknowledgement.
- Use server-issued change cursors rather than client timestamps.
- Commit cloud changes, revision updates, and change-feed entries together.
- Design cursor ordering and pagination so concurrent commits cannot be skipped.
- Apply downloaded content and advance the local cursor together.
- Retry transient failures with backoff.
- Preserve pending edits through authentication, network, and storage failures.

The web app must use the same revision and change-tracking rules so its updates are visible to desktop clients.

### Conflict policy: keep both versions

When both the cloud and offline Mac have changed the same page:

- Preserve the existing cloud version.
- Save the offline version as a clearly labeled conflict copy.
- Notify the user.
- Make retries produce the same conflict copy rather than duplicates.

Conflicting metadata changes must also remain recoverable. An incoming cloud update must not overwrite a locally modified page before reconciliation.

### Deletion handling

- Synchronize deletions using retained deletion records.
- An old offline device must not silently recreate deleted content.
- If a deleted page has offline edits, preserve those edits as recovered content.
- A device with an outdated sync cursor must reconcile safely while retaining pending local work.

### Visible status

Show:

- Saved locally.
- Waiting to sync.
- Syncing.
- Synced and last-sync time.
- Offline.
- Sign-in required.
- Sync failed.
- Conflict copy created.

## 9. Sign-out and local cleanup

**Selected policy: remove local account data after syncing.**

### When online

1. Save current edits locally and pause further editing for sign-out.
2. Complete pending synchronization.
3. Confirm server acknowledgement.
4. End the device session.
5. Remove the account's local notebook cache, assets, and credentials.

Cleanup must be recoverable if the app exits partway through the process.

### When offline or synchronization fails

- Explain that unsynchronized work remains.
- Allow the user to stay signed in and retry later.
- If the user signs out immediately, clear authentication and hide the account's notebooks, while retaining recoverable pending work.
- Completing that deferred upload requires the same account to sign in online again.
- Remove retained data after successful synchronization and cleanup.

Pending work must never be uploaded under another account or silently discarded during sign-out.

## 10. Shared document format and cloud storage

Define one versioned notebook/page format understood by both web and Mac.

It includes:

- Stable notebook, page, and stroke identifiers.
- Explicit page order.
- Page dimensions and paper settings.
- Page-local stroke coordinates.
- Tool, color, width, opacity, and drawing order.
- Asset references.
- Document-format version and synchronization revision.

Rendering and transformations must round-trip between platforms without progressively changing the drawing. The document format is application-owned rather than a serialization of the browser rendering library's scene graph.

### Supabase Postgres

Stores:

- Users and protected application roles.
- Invitations.
- Notebook/page metadata.
- Editable drawing documents.
- Revisions, deletion records, and synchronization changes.
- Operation deduplication records.
- Asset metadata and import progress.

### Backblaze B2

Stores:

- Image and attachment files.
- Thumbnails.
- Native import archives.
- Stored export files.

File access uses authorized, short-lived signed URLs. Upload completion is verified before file references become available. Browser uploads use presigned PUT requests with the required bucket CORS configuration.

Vercel requests and import operations use bounded batches. Large file transfers go directly to B2. Large drawing documents must also be transferred within request limits, with staged updates becoming visible atomically when complete.

## 11. Drawing and notebook features

The drawing-first feature set includes:

- Notebook creation, renaming, searching, and deletion.
- Multiple ordered pages and automatic continuation.
- Blank, ruled, grid, and dotted paper.
- Paper sizes, background colors, and page overrides.
- Pen, pencil, highlighter, and whole-stroke eraser.
- Rectangle, circle, line, and arrow.
- Lasso selection, move, resize, rotate, and delete.
- Undo/redo and keyboard shortcuts.
- Zoom, pan, fit-to-page, and floating tools.
- Page and whole-notebook PDF export.

Web autosave includes recoverable local drafts. Full offline operation is a first-release requirement for the Mac app.

Existing text and image content is preserved during migration. Read-only display of imported text/images is the proposed initial behavior, while the editor focuses on drawing.

## 12. Existing Mac notebook migration

The current app uses a shared local store without account ownership. Migration must explicitly associate existing notebooks with an authenticated account.

Plan:

1. Preserve the original local data during migration.
2. Let the user select legacy notebooks to add to their account.
3. Convert metadata and drawings into the shared document format.
4. Preserve page order, paper settings, stroke styles, and existing attachments.
5. Record migration progress and source identifiers.
6. Make retries safe against duplicate imports.
7. Verify cloud acknowledgement before considering migration complete.

A portable Mac export archive also supports importing through the web application. Import and desktop migration must share source identifiers and deduplication rules.

## 13. Implementation phases

| Phase | Deliverable |
| --- | --- |
| 1. Organization and specification | Repository layout, shared document schema, API contracts, and sync rules |
| 2. Compatibility prototype | Mac/web drawing round-trip, selection correctness, and dense-page performance |
| 3. Accounts and administration | Supabase setup, SMTP, admin bootstrap, invitations, and both sign-in methods |
| 4. Cloud foundation | Notebook APIs, ownership rules, revisions, change feed, and B2 integration |
| 5. Desktop account storage | Authentication gate, per-user stores, downloads, and offline editing |
| 6. Synchronization | Durable queue, bidirectional updates, retries, conflict copies, deletion handling, and sign-out cleanup |
| 7. Complete web experience | Library, editor, autosave, and shared synchronization behavior |
| 8. Migration and release | Legacy Mac migration, PDF export, end-to-end testing, and deployment |

The shared document format and synchronization protocol are early deliverables that guide both applications from the start.

## 14. Release acceptance checks

- One invited user accesses the same notebooks on web and Mac.
- Password and Google sign-in resolve to the correct account.
- Uninvited users cannot access the application through either authentication method.
- Account switching never exposes another user's data.
- Downloaded notebooks remain editable after an offline restart and token expiry.
- Offline edits survive a crash and synchronize exactly once.
- Web changes arrive on Mac.
- Concurrent page edits preserve both versions.
- Deletions do not silently reappear from stale devices.
- Partial downloads resume correctly.
- Interrupted sign-out does not lose pending work.
- Successful sign-out removes the local account cache.
- Legacy import preserves drawings and is retry-safe.
- Admin endpoints reject ordinary users.
- Large notebooks and interrupted file transfers remain recoverable.
- Expired sync cursors recover through reconciliation without losing pending edits.

## 15. Remaining setup decisions

- SMTP provider and verified sending domain.
- Supabase and Backblaze project configuration and regions.
- Application domain and authentication callback URLs.
- Measured initial limits for notebook size, asset size, and storage usage.
- Revision/deletion retention and the stale-device reconciliation window.

**Recommended email setup:** Resend SMTP connected to Supabase.

## 16. References

- [Vercel Hobby plan](https://vercel.com/docs/plans/hobby)
- [Vercel function limits](https://vercel.com/docs/functions/limitations)
- [Supabase sessions](https://supabase.com/docs/guides/auth/sessions)
- [Supabase native authentication callbacks](https://supabase.com/docs/guides/auth/native-mobile-deep-linking)
- [Supabase identity linking](https://supabase.com/docs/guides/auth/auth-identity-linking)
- [Supabase custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp)
- [Backblaze S3-compatible API](https://www.backblaze.com/docs/cloud-storage-s3-compatible-api)
- [Konva document-state guidance](https://konvajs.org/docs/data_and_serialization/Best_Practices.html)
