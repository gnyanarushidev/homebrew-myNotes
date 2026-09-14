# Desktop authentication and account-owned notebooks

**Status:** Implementation plan. Web authentication/cloud drawing and explicit Mac-to-web export/import are implemented; desktop authentication and automatic synchronization are not yet implemented.

## Target experience

1. The Mac app opens an email/password and **Continue with Google** sign-in screen.
2. Supabase authenticates the user; the shared backend validates their administrator or invited-user admission.
3. The app opens the store belonging to the immutable Supabase user ID and downloads that account's notebooks/drawings.
4. On an existing installation, **Import local notebooks** lets the user associate selected legacy notebooks with that account. Originals remain intact until verified migration is complete.
5. Subsequent launches can open that account's downloaded library offline while the user remains signed in. Local edits survive token expiration and restart.
6. Reconnection refreshes the device session and synchronizes pending edits. Sign-out completes pending uploads before deleting the account cache; offline sign-out retains recoverable work behind the sign-in screen.

## Current code and required changes

| Current location | Change |
| --- | --- |
| `desktop app/App/MyNotesApp.swift` | Replace unconditional `LibraryView` and startup store creation with an authentication/account-state root |
| `desktop app/Core/Persistence/DataController.swift` | Create explicit per-account store URLs; retain a separate legacy-store reader; expose recoverable initialization errors |
| `desktop app/Core/Storage/FileStore.swift` | Inject account-specific drawing/asset roots instead of global `Documents/Drawings` |
| `desktop app/Drawing/DrawingStorage/NotebookTransfer.swift` | Reuse export conversion/source IDs for migration and add a native decoder for cloud/web documents |
| `web-app/src/server/http.ts` | Add explicit bearer-token verification for desktop requests while retaining cookie-origin checks for browser requests |
| `web-app/src/server/auth/client.ts` | Share verified administrator/invited-user admission rules across browser and desktop identities |

Proposed new native modules:

```text
App/AccountRootView.swift
Features/Auth/SignInView.swift
Features/Auth/AccountStatusView.swift
Core/Auth/AuthSessionController.swift
Core/Auth/KeychainSessionStore.swift
Core/Auth/DesktopAuthConfiguration.swift
Core/Networking/NotebookAPIClient.swift
Core/Persistence/AccountStoreCoordinator.swift
Core/Sync/SyncCoordinator.swift
Core/Sync/PendingOperation.swift
Core/Migration/LegacyNotebookMigrator.swift
```

## Increment A — Shared API supports native identities

- Add bearer support to protected notebook/import endpoints and an account endpoint such as `GET /api/v1/account`.
- Verify every bearer token with the configured Supabase project's `getUser(token)` (or equivalent verified identity path). Do not trust decoded-but-unverified JWT fields, a requested user ID, or user-editable profile roles.
- Apply the same email-verification and app-access checks as the web app, and return `{ id, email, role, access }` with `Cache-Control: private, no-store`.
- Every notebook query continues to filter by the verified account's `owner_id`, including administrator notebooks.
- Make credential selection explicit: a supplied invalid bearer token fails; it must not fall back to a valid browser cookie. Ambiguous credential combinations receive a documented response.
- Cookie-authenticated mutations continue to require the configured `Origin`. Native bearer mutations do not invent an `Origin` header, but still enforce JSON/schema/body limits. Keep browser CSRF defenses intact.
- Return actionable 401 (refresh/sign-in), 403 (not admitted/revoked), 409 (revision conflict), 413 (request too large), and transient failure responses.

**Acceptance:** valid native tokens can access only their account's notebooks; uninvited, unverified, forged, expired, revoked, and cross-account requests fail; all existing browser auth/CSRF tests still pass.

## Increment B — Native sign-in and Keychain session lifecycle

Use the Supabase Swift SDK through Swift Package Manager with a pinned version selected during implementation. Keep the project URL, publishable key, and API origin in build configuration/Info.plist; no service-role key or admin password is shipped in the app.

### Email/password

- Sign in directly with Supabase and validate admission through the shared account endpoint before opening an account store.
- Registration is invitation-only. Explain pending/revoked/uninvited states and link to invitation/password recovery instructions.
- Reuse web invitation/password-reset setup initially; after the password is set, sign in on the Mac with the same email. Add native recovery callbacks only when they use the same validated callback flow.

### Google

- Use `ASWebAuthenticationSession` with Supabase's OAuth PKCE flow and an app-registered callback, proposed `mynotes://auth/callback`.
- Register `CFBundleURLTypes` and the exact redirect in Supabase. Validate callback scheme, host/path, pending state, one-time PKCE verifier, and cancellation before exchanging the authorization code.
- Let Supabase link supported identities to the same verified user ID; signing in through another method must not create a second local account store for the same user.
- The Google provider callback remains the Supabase HTTPS callback. The native redirect is Supabase → Mac, not Google → arbitrary app URL.

### Sessions

- Store refresh/access credentials using a Keychain-backed SDK storage adapter, partitioned by Supabase project and immutable user ID. No tokens in `UserDefaults`, logs, notebook files, or plaintext JSON exports.
- Serialize refresh through an actor so concurrent API calls share one refresh attempt. Persist rotated refresh credentials before treating refresh as complete.
- Keep browser and Mac sessions independent. Native logout ends the current device session without unnecessarily logging out other devices.
- Tag requests with an account-session generation. Cancel tasks and discard late results whenever the account changes or signs out.

**Acceptance:** password and Google sign-in resolve to the same account; cancelled/stale callbacks cannot change accounts; a Keychain-restored session refreshes once; revoked access returns to an account-status view without deleting pending work.

## Increment C — Account storage and previously authenticated offline access

Use an explicit application-support hierarchy, for example:

```text
Application Support/MyNotes/Accounts/<supabase-user-id>/
  notebooks.store
  Drawings/
  Assets/
  pending-operations.store
  migration-state.json
```

Prefer keeping notebook metadata, pending operations, revision baselines, and cursors in one transactional SwiftData/database store. Drawing snapshots may remain atomic files referenced by those transactions, with recovery for interrupted writes.

Account-root state machine:

```text
launch → restoring credentials
  ├─ no retained signed-in account → signed out
  ├─ online + verified admission → opening account store → ready online
  ├─ offline + previously admitted/signed-in account → ready offline
  └─ refresh/admission failure → sign-in required / access denied

ready → account switch/sign-out → quiesce editor → sync or retain pending work
      → cancel old tasks → close old store → clear credentials/cache as appropriate
```

- Online authentication/admission is required for the first sign-in on that Mac and after explicit sign-out.
- An expired access token during an offline launch does not invalidate previously downloaded local work. Remote revocation is learned after reconnecting.
- An offline-opened store may only belong to the retained, previously admitted account; selecting an arbitrary account directory cannot grant offline access.
- Store opening failures are recoverable UI states, not `fatalError`. Account switching closes the old model container before presenting the new library.

**Acceptance:** two users' notebooks/drafts never mix; account A's delayed network response cannot populate account B; offline restart with an expired access token preserves editing; explicit sign-out hides retained drafts until the same account authenticates again.

## Increment D — Import legacy local notebooks into the authenticated account

- Discover the existing `MyNotes` SwiftData configuration and its referenced global drawing files. Preserve the original store and files; do not move them into the first account implicitly.
- Present a notebook-selection screen with destination account, page/ink counts, and export/skip options.
- Reuse `NotebookWebExporter`'s geometry/style conversion. Add the inverse adapter from validated web polylines/RGBA to `MacStroke` without allocating new IDs or changing drawing order.
- Preserve native text and images; support new cloud image assets and large-document batches before importing notebooks beyond current limits.
- Carry the immutable legacy notebook/page/stroke IDs and a content hash into migration records. Use the same account/source/content mapping as the existing web import so importing the same export by both routes does not duplicate it.
- Commit source → cloud mapping and per-page progress durably. A changed legacy export becomes recoverable additional content instead of replacing newer cloud edits.
- Verify server acknowledgement and content hashes before marking migration complete. Partial failures can be retried after restart; never delete the original source as part of a failed import.

**Acceptance:** transformed drawings and full-precision styles round-trip Mac → cloud → Mac; repeated web/native imports converge; interrupted migration resumes; corrupt/missing files stop the affected notebook with a clear recovery path.

## Increment E — Downloads, offline edits, sync, and sign-out

This increment depends on the synchronization-ready server protocol in `PROJECT_PLAN.md`, not just the current whole-notebook `revision` field.

- Add transactional change-feed cursors, operation deduplication records, revision baselines, deletion records, stale-device reconciliation, and per-page keep-both conflict handling.
- After admission, download all notebook metadata/documents/assets, resume interrupted downloads, and mark **Available offline** only after complete verified local storage.
- Commit each edit and its unique pending operation together locally. Batch bounded uploads and use object-specific B2 signed URLs for assets.
- Sync on login, foreground, local changes, reconnect, periodically while active, and manual **Sync now**. Retain queue entries until server acknowledgement.
- Preserve both sides of cloud/offline conflicts, including edits to deleted pages; retries reuse the same recovered/conflict copy.
- Online sign-out pauses edits, drains/acknowledges the queue, ends the device session, and removes the account cache/Keychain entries through a restart-safe cleanup process.
- Failed/offline sign-out offers retry or immediate sign-out with hidden, retained pending work; deferred upload requires the same account to sign in online again.

**Acceptance:** crash/retry does not duplicate edits; cloud changes arrive on Mac and vice versa; conflicts keep both versions; stale devices cannot silently resurrect deletions; interrupted sign-out cannot discard work.

## Implementation order and release checks

1. Implement A and B together so sign-in always includes backend admission.
2. Implement C before exposing authenticated notebooks on Mac.
3. Finish bidirectional document conversion and the sync-ready backend; then implement D and E in bounded increments.
4. Test on a staging Supabase project with two invited users and separate web/Mac device sessions.

Release checks include Keychain persistence/rotation, Google cancellation and callback replay, uninvited/revoked accounts, account switching with in-flight requests, token expiry offline, restart during migration/sync, simultaneous web/Mac edits, notebook deletion conflicts, and cleanup after sign-out.

**Immediate next development task:** Increment A — bearer authentication and account admission contract — followed by the native sign-in shell and Keychain adapter. The current manual Mac export/web import remains available during this rollout.
