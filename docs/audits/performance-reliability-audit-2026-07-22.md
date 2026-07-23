# Performance and reliability audit — 2026-07-22

## Scope and architecture

Todus is a pnpm/Turborepo product with an active React Router 7 web app, a Hono/tRPC
Cloudflare Worker backed by Postgres/Drizzle, and native SwiftUI iOS/macOS clients.
Web server state uses TanStack Query with IndexedDB persistence. Native clients use
SwiftData plus offline mutation queues. The audited core flows were authentication,
mail list/read/send/schedule/sync, tasks/folders, calendar, docs, onboarding, and AI
entry points. Legacy `apps/mail` and `apps/archived` were excluded.

## Biggest bottlenecks and reliability risks

| Priority | Area                        | Evidence                                                                                                                                      | User impact                                                           | Risk   | Fix                                                                             |
| -------- | --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | ------ | ------------------------------------------------------------------------------- |
| P1       | Web initial load            | `apps/web/app/(routes)/mail/layout.tsx` statically imports the 6.27 MB AI sidebar chunk, and `app-sidebar.tsx` imports state from that module | Every mail route downloads and parses AI before it is opened          | Low    | Extract lightweight AI state hooks and lazy-load the sidebar only when open     |
| P1       | Web onboarding              | `apps/web/components/onboarding.tsx` mounts five eager images, including 45+ MB of GIFs                                                       | First-run inbox transfers about 53 MB and stalls on slow/mobile links | Low    | Render only the active step and replace GIFs with generated MP4 assets          |
| P1       | Web saving                  | `apps/web/providers/query-provider.tsx` retries every mutation once                                                                           | Lost responses can duplicate non-idempotent sends/creates             | Low    | Default mutation retry to false; opt in only per idempotent mutation            |
| P1       | Mail sync                   | `apps/server/src/main.ts` returns 200 when enqueue fails and acknowledges failed thread workflows                                             | Gmail notifications can disappear and inboxes remain stale            | Low    | Return 503 on enqueue failure and explicitly retry failed queue messages        |
| P1       | Scheduled mail              | `apps/server/src/trpc/routes/mail.ts` expires payload/status after 24 hours while supporting longer schedules                                 | Emails scheduled more than one day ahead silently lose their payload  | Low    | Retain KV state through send time plus a bounded retention window               |
| P1       | iOS capture                 | `SupabaseEdgeFunctionClient` erases HTTP status and `SupabaseSyncService` marks malformed/5xx responses permanent                             | A transient backend error can delete a just-created task              | Low    | Preserve status and roll back only explicit non-retryable 4xx responses         |
| P1       | macOS offline tasks/folders | `TaskSyncService` and `FolderSyncService` keep queues only in memory                                                                          | Deletes resurrect and offline edits disappear after termination       | Medium | Persist queued and in-flight mutations, mirroring the proven iOS queue          |
| P1       | macOS account boundary      | local SwiftData rows have no owner and sign-out leaves them intact                                                                            | A second account can see or upload the previous account's local data  | High   | Add durable account ownership/scoping; do not replace this with silent deletion |

## Data loading and rendering

The largest proven loading costs are eager AI code and onboarding media. Mail list and
thread queries also discard error state, so a failed list can look empty and a failed
thread can spin forever. Route-level session loaders repeat session checks and collapse
transient auth errors into logout redirects. These are real reliability issues, but the
auth consolidation changes routing semantics and is kept behind the smaller P1 fixes.

## Data saving and backend behavior

Global mutation retries are unsafe for non-idempotent operations. Scheduled-email KV
retention is shorter than the supported schedule window. Gmail webhook and queue
consumers acknowledge transient failures. Native offline queues are inconsistent across
platforms, and iOS's legacy Supabase path cannot distinguish transient from semantic
rejection. Mail-send idempotency, OTP consumption, and AI credit reservation also need
strongly consistent storage; those require schema/storage design rather than a local
patch.

## Improvement plan

### Priority 1: must fix now

- Fix web eager AI loading, onboarding media transfer, and unsafe mutation retry.
  Files: mail layout, AI state modules, onboarding, query provider. Risk: low. Expected
  impact: much faster first usable inbox and no client-created duplicate writes.
- Fix enqueue/workflow acknowledgement and scheduled payload retention.
  Files: server `main.ts` and mail router. Risk: low. Expected impact: transient failures
  retry instead of losing mail; long-term scheduled mail remains sendable.
- Fix iOS transient-response classification and macOS offline queue persistence.
  Files: native API/sync services. Risk: low to medium. Expected impact: captures and
  offline edits survive outages and process termination.
- Implement macOS account ownership as its own reviewed slice after mapping every
  SwiftData read/write/sync seam. Risk: high because a partial filter is worse than no
  migration. Expected impact: closes cross-account data exposure and upload risk.

### Priority 2: should fix next

- Add explicit Retry UI for failed mail-list/thread queries and bounded retry for network
  or 5xx reads only.
- Move auth protection to a cached parent route and distinguish unauthenticated from
  unavailable; stop protected-data warmups on public and unrelated routes.
- Move macOS JSON decode off the main actor and add bounded calendar pagination.

### Priority 3: optional or architectural

- Replace KV get/put mail idempotency with a strongly consistent reservation and provider
  outcome record.
- Make OTP claiming and AI credit reservation atomic and idempotent.
- Add composite indexes only after production query plans show they are needed.

## Validation contract

Run file-scoped formatting/lint, web and server TypeScript checks, focused unit tests,
the web production build with chunk inspection, native builds/tests for touched targets,
and source-level adversarial checks for dropped responses, 48-hour schedules, transient
task failures, and terminate/relaunch offline queues. Runtime claims require browser,
simulator, or real-account evidence; a clean compile alone is not release proof.

## Implementation and verification results

All P1 items above were implemented. The web mail-list and thread retry states from P2
were also completed because they were low-risk and directly prevent false empty/loading
states. Browser QA then found an anonymous Autumn customer probe returning 401 on every
public route; the bootstrap endpoint now returns an empty customer for anonymous probes
while attach, cancel, track, portal, and entity mutations remain protected.

Measured outcomes:

- The `mail-list` production chunk fell from 5,549.15 kB to 346.14 kB minified
  (2,239.12 kB to 114.21 kB gzip) after removing the full `simple-icons` namespace.
- Onboarding media fell from about 47 MB of GIFs to 4.7 MB of MP4 files, and only the
  active step is mounted.
- The web production build succeeds without the previous CSS syntax warning after the
  CodeMirror selector stopped depending on a generated class. File-scoped web/server
  ESLint is clean.
- Scheduled-email retention tests pass for immediate, 48-hour, and maximum-window sends.
- iOS focused task-capture tests pass 8/8, including 500, 429, malformed 200, and 422
  classification. Touched Swift sources parse cleanly.
- The macOS app compiles successfully with code signing disabled. It now opens a
  hashed, verified-user-ID-specific SwiftData store and mutation journal before the signed-in
  shell renders; stale in-flight work cannot acknowledge or requeue into a new scope.
  Ownerless legacy local data is retained and quarantined for an explicit recovery flow.
  A signed local build is blocked by the machine's stale provisioning certificate,
  not a compile error.
- Public home and login routes render at 1440x900 and 375x812. The stepped email login
  flow and all three MP4 responses were exercised. Protected mail/calendar/docs flows
  still require a real test account and were not claimed as runtime-verified.

The remaining P2/P3 architectural work is recorded in `CODE_REVIEW_BACKLOG.md`; each
item needs a schema, storage, or routing decision and should not be smuggled into this
low-risk remediation pass.

## iOS follow-up — 2026-07-22

The subsequent iOS-focused pass closed the remaining safe native findings and the
calendar-pagination item from P2. Google Calendar list/event calls now follow bounded
pagination and retain cached sources through transient refresh errors. Camera attachments
encode/write off-main. Docs hierarchy rendering uses a mutation-time parent index and title
saves are serialized. Email thread decoding tolerates a malformed optional preview. Local
model availability uses the real Apple Intelligence runtime state, caches stable device
probes, and honors deletions that race the launch scan. Notification scheduling failures are
logged, EventKit queue handoff is Swift 6-clean, and required tab rows cannot be dragged.
The native overflow now contains real Docs, Meetings, and Settings destinations instead of
hidden tab content that could select successfully but render blank. Speech completion callbacks
are lock-protected and return to the main actor without Swift 6 Sendable warnings.

Task capture now uses the authenticated Todus `tasks.sync` tRPC route instead of an unconfigured
legacy Supabase client. Local captures are never deleted because a remote acknowledgement failed;
auth, throttling, timeout, conflict, server, transport, and malformed-response failures preserve
them for retry. Paginated inbound task upserts hydrate after folders without overwriting pending local
edits. Explicit paginated deletion tombstones remove tasks deleted on another device without treating
list absence as proof, stale offline upserts cannot resurrect them, and durable task/folder journals
plus in-flight pulls are invalidated across account changes.
Scheduled-email consumers also stop retrying
stale missing payloads after the retained send window, closing the cancelled-message retry loop.

Verification: iOS `TodusTests` passed 127/127, focused server tests passed 11/11,
file-scoped server ESLint and formatting passed, the iOS Release simulator build succeeded,
and all 10 seeded UI tests passed on a dedicated clean
iPhone simulator. Real Gmail/Calendar account behavior still requires the existing physical-device
release smoke test and is not inferred from seeded UI tests.
