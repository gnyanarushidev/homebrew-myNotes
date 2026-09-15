# MyNotes — Goal, Architecture, Implementation and Operations

This is the single source of truth for the application's goal and implementation plan.

## 1. The goal

MyNotes is initially Rishi's personal application. The Mac app is the primary editor. When the Mac is unavailable, the web app must open and edit the same cloud-synchronized notebooks without requiring the Mac to be running. Family or other users receive access only when the administrator invites them; every account has a private library.

The existing local notebooks, SwiftData relationships, and `/Users/rishi/Documents/Drawings/*.drawing.json` files must remain recoverable. A drawing file belongs to a page; notebook names, page order and paper settings also need synchronization.

### Confirmed storage decision

- Supabase Auth: password/Google identity, verified administrator and invited-user admission.
- Supabase Postgres: **metadata only**—ownership, notebook/page descriptors, B2 references/checksums, revisions, deletion records, operation receipts and migration/sync state. Drawing arrays and image bodies do not belong in the database.
- Private Backblaze B2 bucket: page JSON, images and attachments. The stated budgets are 500 MB of database storage and 10 GB of object storage.
- Mac: account-specific SwiftData and local drawing files, available offline after an admitted sign-in.
- Browser: recoverable account-specific local drafts.

The implementation keeps each live page's current file and one previous drawing/image version, described by current/history manifests. Metadata-only saves preserve the prior drawing version. Referenced files and conflict copies are protected; obsolete objects become eligible for reference-aware cleanup after 24 hours. Never expire every object merely because its upload is old.

## 2. Required experience

1. Sign into the Mac app with email/password or Google. Supabase identity must pass shared backend admission before the account store opens.
2. Associate selected existing local notebooks with that account through a resumable migration; preserve the original store/files.
3. Keep editing normally: commit locally first; upload changed pages in the background; publish metadata only after object verification.
4. Restore the signed-in account offline even if its cloud token has expired. First sign-in and sign-in after explicit sign-out require a connection.
5. Fetch newer cloud content on launch, foreground, reconnect, periodically and through **Sync now**. Pending local edits win protection over incoming replacements; conflicting work becomes a separate recoverable copy.
6. The web client uses the same backend, page JSON and B2 objects. Only successfully uploaded changes are available away from the originating device.
7. Online sign-out freezes edits, synchronizes, clears credentials and cleans the acknowledged account cache. Immediate offline sign-out hides the account and retains unsynchronized work for the same account's next online sign-in.

## 3. Documents and coordinates

- Page-local coordinates, origin top left; X right, Y down. Letter is 612×792 points; A4 is 595×842.
- Zoom and pan are view transforms, never saved into stroke coordinates.
- Native transformed shapes remain polylines. Preserve stroke IDs, order, full-precision RGBA, width and opacity.
- The shared page payload contains versioned stroke data and text; page images are separate objects. Native `.drawing.json` files continue to store editable `MacStroke` arrays, with a lossless adapter at the synchronization boundary.
- Notebook manifests contain title, paper defaults, ordered page IDs/settings, and file descriptors. They contain no strokes or embedded image data.

## 4. Cloud protocol

1. Verify cookie or native bearer credentials and account ownership. An invalid supplied bearer token never falls back to browser cookies. Browser cookie mutations retain same-origin checks.
2. Prepare short-lived signed PUT URLs for bounded page/asset uploads to an account-owned staging namespace.
3. Finalize page files in bounded requests: verify staged bytes, checksum, size and document schema, then gzip page JSON into immutable server-owned canonical objects. A staging URL cannot overwrite a published object. Delete the verified staging version after canonical publication.
4. Atomically commit the manifest, expected revision, operation receipt and account change sequence in Postgres. A retry reuses its operation ID. Failed uploads cannot publish broken file pointers.
5. Reject stale writes or preserve them as a deterministic conflict notebook, according to the client's requested policy. Tombstones prevent stale updates from silently resurrecting a deleted notebook.
6. Reads authorize metadata first, then issue object-specific signed GET URLs. Bucket/application credentials remain server-only.
7. Cleanup serializes with manifest commits and checks current/previous/conflict references before marking/deleting an object. Remove staging leftovers separately after upload expiry.

Publication uses whole-notebook compare-and-swap revisions while transferring page files independently. Clients perform a three-way merge against the last acknowledged document before treating stale revisions as conflicts. Independent page/stroke additions, deletions and metadata changes merge; incompatible edits to the same item preserve both versions. Account change sequences are serialized in Postgres; polling does not rely on device clocks.

## 5. Desktop architecture

### Authentication

- Native sign-in root replaces unconditional opening of the legacy library.
- URLSession talks to Supabase Auth and the shared Next.js API. Password/recovery and Google PKCE use the same Supabase project as the browser.
- Google uses `ASWebAuthenticationSession`, a one-time verifier/state and `mynotes://auth/callback`.
- Keychain retains admitted sessions and rotated credentials. Public API/Supabase configuration is separate from secrets.
- Refresh is serialized; account/session generation checks reject late responses after sign-out or switching.

### Account storage and migration

```text
Application Support/MyNotes/Accounts/<hash-of-api-origin>/<user-id>/
  notebooks.store
  Drawings/
  sync-state.json
```

The legacy `MyNotes` SwiftData store and global Documents/Drawings directory remain the migration source. Copy selected notebooks and referenced drawings into the destination account while preserving IDs. Persist migration progress and verify complete exportability before publishing a notebook. Missing/corrupt files produce an error rather than an empty cloud drawing.

### Durable synchronization

- Local files use atomic writes. The journal stores acknowledged baselines and an immutable pending operation before network transfer.
- A restart scans local notebooks against acknowledged hashes, recovering edits or deletions even if the app exited before its next background sync.
- Keep an upload snapshot stable while newer edits continue locally; acknowledge only that snapshot, then queue later changes.
- Apply remote documents only if the current local snapshot is unchanged. Preserve concurrent local content as conflict/recovery work.
- Download and validate every required file before a remote notebook becomes visible. Retain local pending work on authentication, network or storage failure.

## 6. Implementation order and current work

- [x] Existing Mac editor, desktop-style web editor, invited web accounts, manual Mac export/import.
- [x] Consolidate the agreed personal-app goal and desktop-first/B2 architecture into this file.
- [x] Metadata-only database migration and transactional revision/change tracking.
- [x] B2 staging, verified immutable files, authorized downloads and reference-aware cleanup.
- [x] Shared native bearer admission and public desktop configuration endpoints.
- [x] Native password/Google sign-in, Keychain restore/refresh and account stores.
- [x] Legacy migration and automatic local → cloud synchronization.
- [x] Cloud → local download/reconciliation, conflict preservation and sign-out recovery.
- [x] Existing web clients read/write the same B2-backed records.
- [ ] Production setup and live two-device verification.

## 7. Verification requirements

- Browser and native admission reject uninvited, unverified, forged and revoked identities.
- Two accounts cannot read/sign/upload/commit each other's objects or notebook metadata.
- B2 uploads interrupted before commit do not alter the published notebook.
- Repeated operations acknowledge once; concurrent commits preserve both versions.
- Actual SQL tests cover metadata transactions, reference ownership, deletion records, cursor ordering and cleanup races.
- Native tests cover document round-trip, local atomic state, migration preservation, pending operation recovery, token/callback validation and account switching.
- Build both the web and Mac applications; retain existing drawing/selection regressions.
- Hosted smoke checks use separate browser/Mac sessions and verify actual B2 objects plus metadata-only database rows.

## 8. Deployment and configuration

Use one Next.js/Vercel deployment under `web-app/`, Node.js 24. Server settings:

```text
APP_URL
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
SUPABASE_SECRET_KEY
ADMIN_EMAIL
B2_ENDPOINT
B2_REGION
B2_BUCKET_NAME
B2_APPLICATION_KEY_ID
B2_APPLICATION_KEY
```

Use a private B2 bucket and a restricted application key. Browser bucket CORS must allow the application's exact origins and signed GET/PUT requests with their required headers. Configure Supabase custom SMTP and Google before inviting ordinary accounts.

Apply versioned SQL migrations in order. The original `001_notebooks.sql` is a legacy JSONB store; existing rows must be transferred and verified before their payloads are retired. A web deployment does not execute migrations automatically.

Desktop configuration should use the deployed API origin; the public configuration endpoint supplies the matching Supabase URL/publishable key. Add the native PKCE redirect pattern described by the implementation to Supabase's allowed redirects.

### Activate this implementation

1. In the configured Supabase project's SQL Editor, apply `web-app/supabase/migrations/001_notebooks.sql` if it was not previously installed, then the complete `002_cloud_storage.sql`. The new tables are `cloud_notebooks`, `cloud_objects`, `cloud_references`, `cloud_operations` and `cloud_accounts`. The current application writes drawing payloads exclusively to B2.
2. Set the server variables above in Vercel and redeploy with Root Directory `web-app`, Node.js 24. Never put the B2 secret or Supabase server secret into the Mac app or browser configuration.
3. Configure Supabase's existing web callback URLs, and add the native pattern **`mynotes://auth/callback?state=*`** to allowed redirects. Google Cloud continues to use the Supabase HTTPS provider callback. Native email invitation/password setup initially uses the existing web email links.
4. Configure bucket CORS for `GET`, `HEAD`, `PUT`, the application's exact origins, and request headers used by signed uploads. The helper below preserves other CORS rules and updates only the MyNotes rule:

   ```sh
   npm --prefix web-app run cloud:configure-b2 -- --origin https://mynotes.gnyanarushi.tech --origin http://localhost:3000 --apply
   ```

5. In B2 lifecycle settings, use a rule scoped **only to `staging/`** to expire abandoned uploads/hidden staging versions after a short grace period (recommended: hide after one day, delete one day after hiding). Published files live under `users/` and must use application reference-aware cleanup instead of age-only expiration. Successful finalized staging versions are already removed by the application.
6. Run `npm --prefix web-app run cloud:check` (read-only). The check verifies metadata-table availability, bucket reachability/privacy and browser CORS.
7. Build/run the current Mac sources using `zsh "desktop app/run-macos.sh"`. Sign in, open the native toolbar's **cloud icon**, then choose **Import existing local notebooks → Import and synchronize**. Original SwiftData and Documents/Drawings files remain intact. Migration ownership/progress is retained separately from removable account caches.
8. If older web notebooks exist in the legacy JSONB table, use **Move older cloud notebooks to B2** in the web sidebar. The server moves bounded batches, verifies publication, and retires only the exact acknowledged legacy rows; conflicts create copies.
9. Sign into the web app and verify the same notebook and drawing. Edit it there, return to the Mac, and use **Sync now**. Verify a subsequent offline Mac restart and sign-out with pending edits on a test notebook.

### API contract

| Endpoint | Purpose |
| --- | --- |
| `GET /api/v1/config` | Public Supabase URL/publishable key for the matching application deployment |
| `GET /api/v1/account` | Verified admitted identity; cookie or native bearer credentials |
| `GET /api/v1/sync?cursor=N` | Bounded account change feed, including deletion records |
| `GET /api/v1/sync/notebooks/<id>?downloads=1` | Owned manifest and short-lived signed object downloads |
| `POST /api/v1/sync/uploads` | Signed, size-bound staging PUT URLs |
| `POST /api/v1/sync/files` | Bounded file verification/compression/finalization |
| `POST /api/v1/sync/commit` | Revision-checked atomic metadata publication and operation receipt |
| `POST /api/v1/sync/cleanup` | Restartable cleanup of unreferenced canonical file versions |
| `GET /api/v1/sync/usage` | Account's tracked B2 object bytes and notebook count |
| `GET/POST /api/v1/sync/legacy` | Detect/migrate the original web JSONB documents |

### Current limits and behavior

- Automatic transfer: 16 MB uncompressed page JSON, 8 MB per image, 128 MB aggregate notebook content, and 300 pages. Transfers go directly to B2; the metadata commit stays small. Manual JSON import/export retains its earlier 2.9 MB bound.
- Mac sync runs on opening the account, foreground, every 15 seconds and **Sync now**. Periodic attempts recover connectivity automatically. Incoming content waits for active drawing gestures and protects pending local snapshots.
- Desktop account/sync controls live in a compact cloud-icon toolbar menu. Sync status, storage usage and import reports are available through **Sync details…**; they do not occupy a separate full-width bar above the notebook canvas.
- Open web notebooks have no horizontal top header bars. The drawing palette floats over the full-height canvas, with undo/redo alongside the drawing tools. A compact bottom notebook menu contains naming, paper/page controls, PDF/JSON export and manual save; page navigation and zoom remain in the bottom control strip.
- The web sidebar footer is a single account menu. Account settings, invitations, storage usage and sign-out appear on demand, while notebook counts stay beside the library heading. Menus support Escape/outside-click dismissal and adapt to small screens.
- Web cloud refresh runs on foreground/every 15 seconds while clean; unfinished gestures and dirty drafts are protected. New remote content invalidates stale local undo history.
- Global web search currently searches notebook titles. Page text stays in B2; Mac search can still search downloaded page text locally.
- Clients merge non-overlapping changes using stored baselines. Whole-notebook conflict copies are reserved for incompatible edits or an unavailable historical baseline. Deleted notebooks keep small tombstones; deleted file content becomes cleanup-eligible once unreferenced.
- B2 usage shown in the clients covers registered canonical/history files, excluding transient staging uploads and unrelated legacy bucket files. The B2 console remains authoritative for total billed storage.
- Compact operation receipts/tombstones are currently retained. A bounded retention/reconciliation protocol is a remaining scale milestone; there is no claim of unlimited use within the storage allowances.

### Live readiness check

The configured B2 bucket is reachable and private, the application GET/PUT CORS rule is present, and the live Supabase cloud metadata tables are accessible. The legacy-import/concurrent-sync repair was deployed as commit `696fa68` (public configuration reports sync protocol 2). The updated Mac app resumed the admitted account and completed the legacy import. Google-specific sign-in and extended offline/account-switch scenarios remain separate release checks.

Automated regressions use isolated test stores and transports. The live repair below used the signed-in Mac application to copy and synchronize the actual legacy notebooks; the original legacy store and drawing files were retained.

### Verification completed for this implementation

- Node.js 24 lint/type checks and production web build passed.
- **22 browser/API tests** passed against a local S3-shaped object fixture and the actual PostgreSQL cloud transaction functions.
- **7 PostgreSQL migration tests** passed, including receipt replay, conflicts, tombstones, ownership, previous-file retention across metadata-only saves and cleanup exclusion.
- Unsigned **macOS build passed**.
- **9 native cloud/account regressions**, **8 selection regressions** and **5 transfer regressions** passed. Tests use isolated temporary stores and fake cloud transport, including lost-acknowledgement restart, deleted-notebook recovery and source-data preservation.
- Web checks remain in CI; a native build/regression workflow was added for Mac source changes.
- The initial missing-migration blocker has been resolved. Current live storage and legacy-repair results are recorded below; the initial checks used local fixtures before activation.
- A temporary synthetic B2 object verified real gzip upload/download and exact-version deletion; its version was removed. This did not upload personal notebook contents. Canonical uploads reserve metadata first, so interrupted publication remains discoverable by cleanup.

### Legacy import and false-conflict repair

- The real legacy store contained 5 notebooks/24 pages. Two notebooks had finite off-page coordinates beyond the provisional ±10,000 validation bound, causing import to stop before the rest could be imported.
- Storage validation now preserves all finite coordinates; rendering still clips to the page. Source stores open read-only, migration continues past an individual failure, and the app reports found/imported/skipped/failed counts.
- The corrected read-only inspection validated all 5 notebooks and 5,270 strokes. The original drawing files remain the source of truth during this repair.
- Both clients merge independent changes by stable page/stroke IDs. The Mac persists complete acknowledged merge baselines and rebased pending operations, checks operation receipts before retrying, and preserves edits made while a merged upload is in flight.
- The browser persists rebased drafts and no longer treats an optional post-commit metadata-read failure as a failed save. Requests are bound to the account that started them.
- Added regressions for concurrent stroke additions without copies/echoes, metadata merging, lost merged acknowledgements, off-page legacy coordinates and partial-import reporting. Verification passed: 25 browser/API/merge tests, 7 database tests, 13 native cloud/merge tests, 8 selection tests, 5 transfer tests, and web/macOS builds.
- Live repair completed: all 5 legacy notebooks / 24 pages / 5,270 strokes were imported and synchronized. Combined with the pre-existing notebook, desktop and cloud contain 6 live notebooks / 26 pages. All 24 imported B2 page files passed checksum verification, including 49 strokes beyond the former coordinate bound. Local imported document digests match the original legacy snapshots.
- The native journal reported 6 acknowledged baselines, 5 migrated source notebooks, no pending operation and a clean synchronized state. Imported notebooks remained at revision 1 during subsequent idle sync checks; no new conflict copies were created by the import. Refresh existing web tabs to load the deployed merge behavior and updated library.
- Optional local diagnosis: `bash "desktop app/Tests/run-regressions.sh" --inspect-store <store-path> <drawing-directory>` reads counts and validation results without modifying the source.

## 9. Later milestones

- Complete web/Mac synchronization release checks, including extended offline sessions and additional merge cases.
- Bounded synchronization/operation retention with explicit stale-device reconciliation.
- Large assets/staged imports beyond the initial measured page limits.
- Full-text search strategy that does not duplicate drawing payloads in Postgres.
- Independent invitation expiry/acceptance audit history.
- Browser multi-tab draft isolation and dense-page performance work.

## References

- [B2 S3-compatible API](https://www.backblaze.com/docs/cloud-storage-s3-compatible-api)
- [B2 lifecycle rules](https://www.backblaze.com/docs/cloud-storage-lifecycle-rules)
- [Supabase sessions](https://supabase.com/docs/guides/auth/sessions)
- [Native authentication callbacks](https://supabase.com/docs/guides/auth/native-mobile-deep-linking)
