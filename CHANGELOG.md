# Project Changelog

## [Unreleased]

### Added

#### Web → Native parity (workstream A1) — calendar event editing
- **Web calendar can now create, edit, and delete events** — `/mail/calendar` was previously read-only (it rendered Google Calendar events + task due-dates but had no write UI; the `calendar.createEvent/updateEvent/deleteEvent` mutations existed server-side but nothing called them). Added an `EventEditDialog` (title, all-day toggle, start/end, location, notes — mirrors the native macOS `MacEventEditSheet` field set) wired to those mutations. A header "New event" button and tapping an empty time-grid slot open the create dialog; clicking an event opens edit; delete lives in the dialog. All-day events handle Google's exclusive `end.date` correctly (no off-by-one). Scoped to the primary calendar; multi-calendar visibility toggles are the next workstream (A2). The left-rail quick-add still creates tasks (unchanged). Date/timezone/all-day/payload logic is a pure, unit-tested module (`lib/calendar-event-form.ts`, 13 tests). Also enabled vitest for `apps/web`. See `docs/superpowers/specs/2026-06-13-web-native-parity-MASTER-design.md`. (`apps/web/app/(routes)/mail/calendar/page.tsx`, `apps/web/components/calendar/event-edit-dialog.tsx`, `apps/web/lib/calendar-event-form.ts`)

#### Web → Native parity (workstream A2) — multi-calendar visibility
- **The web calendar now shows all your calendars with per-calendar visibility toggles** — it previously only ever fetched the `primary` calendar (`calendarId` hardcoded). Switched to `calendar.eventsMulti` (spans all connections; each event tagged with its `calendarId`), added a left-rail "Calendars" list with color swatches + visibility toggles (persisted in localStorage, device-local like native), and replaced the `settings/calendars` placeholder with the same real toggles (kept in sync). Event edit/delete now target each event's own calendar instead of always `primary`. (`apps/web/app/(routes)/mail/calendar/page.tsx`, `apps/web/lib/calendar-visibility.ts`, `apps/web/app/(routes)/settings/calendars/page.tsx`)

#### Web → Native parity (workstream B1) — AI can manage tasks
- **The AI assistant can now create, update, complete, and list tasks** — `apps/server/src/routes/agent/tools.ts` previously exposed email tools only, so asking the chat (or voice) assistant to "add a task" silently did nothing. Added `createTask`/`updateTask`/`completeTask`/`listTasks` agent tools (mirroring the `tasks.create` insert, user-scoped via the resolved `userId`). **Also fixed a latent correctness gap:** the `aiCanWriteTasks` permission (Settings → AI → Permissions) was saved by the web settings page but never enforced server-side — write-task tools are now gated behind it (reads stay available). (`apps/server/src/routes/agent/tools.ts`, `apps/server/src/types.ts`)
- **The AI assistant can now create calendar events** (B2) — added a `createEvent` agent tool that writes to the user's primary Google Calendar (reusing the calendar route's Google client, now exported), handling timed (ISO + offset) and all-day (exclusive end) events. Gated behind `aiCanWriteCalendar` (also previously saved-but-unenforced). (`apps/server/src/routes/agent/tools.ts`, `apps/server/src/trpc/routes/calendar.ts`)

#### Web → Native parity (workstream E) — share-conversation UI
- **Web can now create share links for AI conversations** — the `sharing.create` backend existed (password + expiry), and `settings/sharing` could list/revoke, but there was no UI to actually *create* a share (native has the share sheet). Added `ShareConversationDialog` (title, optional password, expiry: never/1/7/30 days) + a "Share" button in the chat header; shows a copyable `/share/:slug` link. (`apps/web/components/ai/share-conversation-dialog.tsx`, `apps/web/app/(routes)/mail/chat/page.tsx`)

#### Web → Native parity (workstream C) — voice transcript
- **Web voice now shows a live transcript** — the voice call was "blind": nothing displayed what was said. The `onMessage` handler was also attached to `startSession` instead of the `useConversation` hook (where ElevenLabs' `HookCallbacks` live), so it likely never fired. Moved it to the hook, collect the transcript into provider state, and render a compact transcript panel above the voice button. Also added the missing `connectionType: 'webrtc'` (cleared a pre-existing type error). Voice *tool execution* (create task/event during a call) is still off — it needs the ElevenLabs agent configured in the dashboard; tracked as backlog PAR-C. (`apps/web/providers/voice-provider.tsx`, `apps/web/components/voice-button.tsx`)

### Fixed

#### App Store submission audit
- **iOS account deletion no longer masks backend failure as success.** If the
  `delete-user` request fails, Settings now shows a retryable error and keeps the
  session intact instead of signing out locally and implying the account was
  deleted. Also fixed an inverted backend revocation log condition in the same
  deletion path, and updated the Docs parity smoke test to skip when the current
  More surface does not expose Docs in `--ui-testing` mode. Added
  `APP_STORE_AUDIT.md` with the current App Store Review readiness matrix and
  required pre-submission fixes. (`SettingsView.swift`, `auth.ts`,
  `ParitySmokeTests.swift`, `APP_STORE_AUDIT.md`)

#### Backend efficiency + correctness pass (server-only)
- **B-025 — generative-UI prompt no longer forced on every client.** The ~21KB `GENERATIVE_UI_PROMPT` was injected into every `/ai/chat` system prompt regardless of whether the client could render the cards. Added an optional `supportsGenerativeUI` flag to the chat request schema (default `true`, backward compatible) and gated the injection on it; the duplicate injection in `lib/prompts.ts` (`AiChatPrompt`) is now gated behind an optional `{ generativeUI }` option (default `true`). Clients that only render markdown can now opt out and save the tokens. (`apps/server/src/routes/ai.ts`, `apps/server/src/lib/prompts.ts`)
- **B-028 — auto-labeling is now a user-controllable automation.** Added `autoLabelThreads` (default `true`) to `assistantAutomationPolicySchema` + `defaultAssistantAutomationPolicy`, and gated `labelGenerationWorkflow` registration behind it in the thread-sync engine. `vectorizationWorkflow` stays unconditional (inbox search/RAG depends on it) with a comment noting it's intentionally always-on. (`apps/server/src/lib/schemas.ts`, `apps/server/src/thread-workflow-utils/workflow-engine.ts`)
- **B-015 (KV-cache half) — sender-avatar resolution is cached in-isolate.** Replaced the "no KV binding available" TODO with a module-level in-memory cache (`Map` keyed by normalized email + externalImages flag, ~24h TTL, 2000-entry LRU-ish cap) around the deterministic (non-Google) resolution path in `resolveSenderAvatar`. Eliminates repeat third-party hits (favicon scrape, Gravatar, BIMI DNS, Clearbit) for the same sender within a warm isolate. Per-user Google People lookups bypass the cache (must never be shared across users). The privacy `externalImages` gate is preserved. (`apps/server/src/lib/sender-avatar.ts` + test)
- **subscription `getStatus` now returns the active `productId` + `interval`.** The cached read only exposed a coarse `plan` ("pro") and couldn't distinguish `pro_monthly` from `pro_annual`, so clients couldn't cancel the correct product. `getStatus` now resolves the real active product id from Autumn (new `getActiveProduct` helper, fails soft); free plans skip the round-trip (`productId: "free"`). (`apps/server/src/lib/billing.ts`, `apps/server/src/trpc/routes/subscription.ts`)
- **PAR-A2 (server half) — calendar write/read can target a non-active connection.** `createEvent`/`updateEvent`/`deleteEvent` now accept an optional `connectionId` and resolve it user-scoped via `findUserConnection` (no IDOR; omitted = active connection, backward compatible; bad id → `NOT_FOUND`). Added a `calendarsMulti` query returning calendars across ALL the user's Google connections, grouped/annotated by `connectionId` + email with per-group `scopeMissing`/`error`. (`apps/server/src/trpc/routes/calendar.ts`)

#### Full-repo review pass (2026-06-13)
- **macOS Billing tab could crash on a corrupted credit value** — `MacSettingsView.formatCredits` fed `aiUsageUsed`/`aiUsageLimit` straight into `Int(scaled.rounded())`, which traps on NaN/±infinity/overflow (e.g. an upstream divide-by-zero or bad decode). Added the same `scaled.isFinite` + `scaled < Double(Int.max)` guards iOS `BillingSettingsView.formatCredits` already has (render `"—"`), keeping the three platforms in sync. Also removed a stale self-contradicting `TODO` in `SupabaseSyncService.retryUnsyncedTasks` (already wired via `NetworkMonitor.onReconnect`) and a wrong "bottom-left" FAB comment in `CalendarTabView`. Remaining findings (incl. a critical offline-capture data-loss gap on server 5xx/429 and the macOS `TodusMacTests` target missing from the regenerated pbxproj) logged in `CODE_REVIEW_BACKLOG.md` (CR-0613-1…16). (`MacSettingsView.swift`, `SupabaseSyncService.swift`, `CalendarTabView.swift`)

#### macOS email reliability pass (`/goal` QA session) — emails not loading, thread-open errors, hangs
- **Connected users were parked on the "Connect Gmail" onboarding prompt (blocker)** — `EmailService.checkConnection` set `hasConnection=false` on *any* thrown error (8s timeout, offline, transient 5xx), and `ensureMailboxReady` then `guard hasConnection`'d out, so a single flaky `connections.list` call left a fully-connected user staring at the connect prompt with no error and no retry. Now only a *successful* empty response sets `hasConnection=false`; failures set a new `connectionCheckFailed` flag and preserve a known-good connection. Added a `connectionCheckFailedState` ("Couldn't reach your mailbox" + Try Again) so transient failures show a retry instead of the wrong onboarding state. (`EmailService.swift`, `MacEmailInboxView.swift`)
- **401 routed to the wrong empty state + showed no error** — `loadThreads`'s `catch APIError.unauthorized` set `hasConnection=false` (→ "Connect Gmail") and left `errorMessage` nil (silent dead inbox). Now surfaces "Your session expired. Please sign in again." and leaves connection state intact; the API client already flips `isSessionExpired` for the root view to drive re-auth. (`EmailService.swift`)
- **The "errors when entering email threads" crash (high)** — `mail.get` returns every message of a thread in one payload, but `EmailSender.email` and `EmailMessage.sender` were *required* decodes. A single message with a null/missing sender or null email threw a `DecodingError` that aborted the **whole** thread decode → hard "couldn't load thread" error screen. Email decode is now tolerant (`email` → `""`, missing sender → "Unknown sender" placeholder), and `GetThreadResponse` decodes messages element-by-element via `FailableDecodable<EmailMessage>` so one malformed message is dropped, not fatal. (`EmailModels.swift`, `EmailService.swift`)
- **Request timeouts didn't promptly stop the underlying work** — added `try Task.checkCancellation()` at the top of `TodosAPIClient`'s retry loop so a cancelled/timed-out request stops instead of burning another attempt + full URLSession timeout. `loadThreads` now gives timeouts distinct copy and treats `CancellationError` (folder switch / view torn down) as a non-error. (`TodosAPIClient.swift`, `EmailService.swift`)
- **Thread-open main-thread stall on large emails** — `recomputeFallbackChips` ran a full-document `<[^>]+>` regex strip on the main actor at open (visible stutter on big newsletters); input is now capped to 20k chars (verification codes/tracking numbers live near the top). `markAsRead` is gated on a successful load so a failed/cancelled open no longer marks unseen mail read. (`MacEmailThreadView.swift`)
- **Pagination failure caused a tight backend-hammering retry loop** — a failed "load more" set an (invisible-because-list-non-empty) error and left the cursor, so the paginator's `.onAppear` re-fired immediately on every `LazyVStack` rebuild. Added a `paginationFailed` flag + an explicit "Couldn't load more — Retry" footer; auto-fire is now gated on it. (`EmailService.swift`, `MacEmailInboxView.swift`)
- **Tests** — `TodusMacTests/EmailDecodeToleranceTests.swift` (XCTest, real types) + `scripts/run-email-decode-tests.sh` (Xcode-free runner compiling the real `EmailModels.swift`); decode-tolerance + one-bad-message regressions 11/11 green. Test target is defined in `project.yml` but not yet runnable via `xcodebuild test` — see `CODE_REVIEW_BACKLOG.md` MAC-1 (MLX C-module resolution in the testable host build). App `BUILD SUCCEEDED`.

#### iOS performance + reliability pass (`/goal` QA session) — main-thread freezes, thread-open errors
- **All tRPC response parsing/decoding ran on the main actor (freezes)** — `TodosAPIClient` is `@MainActor`, so `JSONSerialization` + `Decodable` work for every response — including the 50-thread inbox batch and `mail.get` payloads carrying full HTML bodies (hundreds of KB) — blocked the main thread for the whole parse. This fired on every 60s inbox poll, foreground refresh, pull-to-refresh, thread open, and the 8-thread prefetch, matching the reported "stutters and freezes when tapping/navigating". `trpcSingle` and `trpcBatchQuery` now hand the response `Data` to a detached `.userInitiated` task for parse + decode (`serializeJSONValue` made `nonisolated`; trpc generics gained `& Sendable`, zero call-site fallout). (`TodosAPIClient.swift`)
- **`apiDecoder` allocated up to 2 `ISO8601DateFormatter` per Date field** — the custom date strategy built formatters inside the per-date closure; payloads with hundreds of dates burned visible decode time. Hoisted to shared parse-only formatters (same pattern as `EmailMessage.parseDate`). (`TodosAPIClient.swift`)
- **Avatar disk cache did synchronous disk I/O on the main thread per row (scroll jank)** — `CachedAvatarImage.onAppear` ran `Data(contentsOf:)` + JPEG decode on main for every row scrolling into view, and the network path wrote the JPEG to disk on main. Reads/writes moved to detached background tasks; UI applies the decoded image on main. (`AppTheme.swift`)
- **Sender avatars in the inbox/People/search now downsample + disk-cache (EM-1/EM-3)** — `SenderAvatarView` rendered the favicon/photo waterfall via raw `AsyncImage`, which decoded the full-size (often 256–512px) source on the main thread and bypassed the on-disk image cache entirely (`AvatarCache` only cached the URL list). Added `AvatarImageLoader` (ImageIO `CGImageSourceCreateThumbnailAtIndex` downsample to `pointSize × screen scale`, off-main, persisted to the shared `AvatarDiskCache` as a compact JPEG, plus an `NSCache` of decoded images). The waterfall, person-photo-vs-brand-logo treatment, `recordSuccess` reorder, and `resolvedCandidates` snapshot logic are unchanged — `WaterfallAvatarImage` advances `urlIndex` on load failure exactly as the old `.failure` branch did, and rejects non-2xx responses so 404 favicons still advance the waterfall. (`apps/ios/Todus/Todus/Features/Email/SenderAvatarView.swift`)
- **Inbox search re-lowercased every thread's four fields on every keystroke (EM-7)** — `recomputeFilteredThreads` lowercased subject/name/email/snippet for the whole list per character. Now a per-thread lowercased search blob is precomputed once into a `@State` dict whenever `emailService.threads` changes, and filtering matches against that. The `SenderThreadsView` per-sender list also re-filtered + re-sorted the whole inbox on every body evaluation (every swipe-action render); it's now cached in `@State`, recomputed only on threads/query change. (People-mode grouping was already gated/cached.) (`apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`)
- **Calendar Day view only showed Apple events (H9)** — CalendarKit's day timeline owned its own `EKEventStore`, so Google/CalDAV events never appeared in Day mode (the app fetched the unified list only for a "switch to Multi-Day" banner). Day mode now renders the unified single-column grid via `CalendarMultiDayView(dayCount: 1)` — the same renderer Multi-Day uses (all-day bar, now-line, event/empty-slot taps wired to the existing `presentEvent` / create-sheet flow) — so all sources show. Day now anchors on `selectedDate` like the other modes (gaining prev/next/today via the shared `CalendarNavBar`); the banner and the dead CalendarKit day-view state (`dayViewDisplayedDay`, `dayGoToTodayTick`, `hasNonAppleEventsToday`, save-error alert) were removed. (`apps/ios/Todus/Todus/Features/Calendar/CalendarTabView.swift`)
- **Opening a thread could flip a readable (cached) thread into "Could not load thread"** — `EmailThreadView.loadThread` paints instantly from the detail cache, but the concurrent silent `markAsRead` invalidates that cache entry, forcing the parallel refresh to the network; a transient failure then assigned `detail = nil`, replacing visible content with the error state. `detail`/`isStarred` now only update when the fetch actually returned something. (`EmailThreadView.swift`)
- **Verification-code "Copied" label could flicker back early on rapid re-taps** — the 1.5s revert task wasn't cancelled on re-tap. Now tracked + cancelled. (`EmailThreadView.swift`)
- **Tests** — `TodosAPIClientTests`: apiDecoder fractional/plain/garbage ISO dates; off-main envelope decode with Date fields; batch success+error positional mapping; batch count-mismatch throws. 94/94 unit tests green.
- **XCUITest harness repairs (3 of 5 critical-flow tests were failing; all 5 now green)** — C3: the `--ui-testing` seed never set `hasSeenWelcomeTour`/`hasConfiguredTabBarPrompt`, so on a fresh test container the first launch landed on the welcome tour instead of MainTabView (the flags were only migrated to "done" from a *previous* launch's `hasReachedMainTab`); now seeded explicitly. C3/C4: the simulated pending-AI-mutation stub flipped `showsAIChat` + set `pendingMutationConfirmation` during initial mount — the sheet presentation got silently dropped (and `onDismiss` reset the flag) and `confirmationDialog` skips presenting mid-sheet-transition; the stub now stages both (sheet at +700ms, dialog at +1.6s). C3/C4 tests also assumed a Cancel button, but iOS 26 renders `confirmationDialog` as a compact alert with NO accessible Cancel — tests now match the titled dialog sheet and resolve via the visible action button. C2: `accessibilityIdentifier("email.thread.<id>")` on the thread ZStack cascaded onto leaf children with no container element, so `otherElements[...]` never matched (navigation itself worked); added `.accessibilityElement(children: .contain)`. (`AppServices.swift`, `TodosApp.swift`, `EmailThreadView.swift`, `CriticalFlowsTests.swift`)
- **Local model downloads broken on iOS** — iOS Xcode project was missing the `mlx-swift-examples` Swift Package entirely, so `#if canImport(MLXLLM)` always fell through to the stub branch, surfacing "MLX is not available in this build." Added `XCRemoteSwiftPackageReference`, linked `MLXLLM` + `MLXLMCommon` products to the Todus target, and added them to the Frameworks build phase.
- **Local model downloads broken on macOS** — `mlx-swift-examples` was referenced in `packageReferences` but no `XCSwiftPackageProductDependency` section existed, so the products were never linked. Added the missing dependency section and wired `MLXLLM` + `MLXLMCommon` into the TodusMac target.
- **`LocalModelStateStore.initialScan` looked at the wrong directory** — scanned `Application Support/LocalModels/<id>` while downloads actually land in `Documents/huggingface/models/<repo>` (where `mlx-swift-examples` writes). Models installed across launches now show as "Installed" in the Local Models screen. Both iOS and macOS fixed; the macOS scan also falls back to the user's `~/.cache/huggingface/hub` so models pulled outside the app via `huggingface_hub` or `mlx_lm` get recognized.
- **iOS MLXInferenceService Swift 6 strict-concurrency compile error** — captured `[Chat.Message]` in a `@Sendable` closure. Switched to the plain dict shape (`[[String: String]]` + `UserInput(messages:)`), matching the macOS implementation. Added `@unknown default` to the event switch.
- **macOS build was broken (would not compile)** — `MacMarkdownBodyEditor.Coordinator` held `lazy var textView = NSTextView()` and called `selectedRange()`/`textStorage`/`string`/`setSelectedRange` from a nonisolated context; under the macOS 15 SDK + Swift 6 these AppKit members are `@MainActor`-isolated, producing a hard error plus 11 warnings. Annotated the `Coordinator` `@MainActor` (all access already happens on the main thread). Build now compiles.
- **macOS `MLXInferenceService` non-exhaustive switch** — the `Generation` event stream switch handled `.chunk`/`.info` + `@unknown default` but not the known `.toolCall` case. Added `case .toolCall: continue` (local v1 doesn't surface tool calls; keep streaming).
- **macOS chat dropped trailing tokens / cross-talk between streams** — the streaming token flush (`MacAIChatService.appendToken`) was gated by a `flushScheduled` Bool whose pending `asyncAfter` could not be cancelled. A stale flush firing ~40 ms after a stream ended could write the *next* stream's buffered tokens into the *previous* message bubble. Replaced with a cancellable `DispatchWorkItem` that `cancelStream`/`finaliseStream` cancel.
- **macOS voice panel observation/concurrency warnings** — `pcmBuffer`/`_micMutedAtomic` (lock-guarded, mutated on the audio thread) were `nonisolated(unsafe)` inside a `@MainActor @Observable` class, which also let SwiftUI observe background-mutated state. Marked `@ObservationIgnored nonisolated(unsafe)`.
- **iOS `--ui-testing` launch arg signed the test session out (XCUITest blocker)** — the seeded session (`uitest@todus.app`, fake `TEST_TOKEN`) reached `MainTabView` but a tab's first authenticated request 401'd against production, triggering `AuthService.attemptSilentRefresh()` → `/auth/me` 401 → `signOut()`, bouncing back to the login screen ~1s after launch. Added `AuthService.isUITestingSession` (set by `_uiTesting_seedAuthenticatedSession`) so `attemptSilentRefresh()`/`fetchUserProfile()` skip the network and never sign out, and `TodosAPIClient` suppresses the "Session expired" banner in test mode. All guards default off in production (no behavior change). (`packages/swift-auth/.../AuthService.swift`, `apps/ios/.../TodosAPIClient.swift`)
- **iOS thread reply bar / "Draft with AI" actionable before load** — Reply/Reply All/Forward are now `.disabled` until the thread `detail` loads; the AI-draft FAB is `.disabled` while `emailService.isSending`. Prevents acting against a nil last-message / double-submit. (`EmailThreadView.swift`, `EmailComposeView.swift`)
- **iOS GroupChat missing loading/empty states** — group list and message list now show a spinner during first load and a "No messages yet" empty state instead of briefly flashing empty copy. (`GroupChatView.swift`)

#### iOS Simulator QA pass — found by driving the app in the iPhone 17 / iOS 26 simulator (`--ui-testing`)
- **Captured tasks could vanish silently (high, data-loss/trust)** — when a just-captured task fails to sync, `TaskCaptureService` rolls it back (deletes it) and publishes `lastRollbackCount`/`lastRollbackAt` "so views can surface a banner" — but no view observed them, so the task disappeared with zero feedback. `MainTabView` now shows a transient "Couldn't save your task — check your connection" banner on rollback (stacked with the offline / session-expired banners in a `VStack` so they no longer overlap). Validated in-sim: the banner appears on the seeded-token sync failure. (`MainTabView.swift`)
- **Could not type a second email recipient (high)** — To/Cc/Bcc bound a `TextField` to a computed `Binding` over `draft.to: [String]` that re-tokenized on every keystroke, so a typed `,`/`;` separator was eaten and only the first recipient stuck (paste still worked). Each field now binds to a raw `@State` string, tokenizing into `draft` on change + before send, seeded from `draft` on appear. Validated in-sim: `a@b.com, c@d.com` both stick. (`EmailComposeView.swift`)
- **Tasks empty-state copy pointed the wrong way** — "Tap + **above** to capture…" but the create button is the floating FAB at the bottom; changed to "Tap + to capture…". (`InboxView.swift`)
- **Home section-header icons leaked SF Symbol system names to VoiceOver** — decorative `envelope.fill` / `video.fill` / `folder.fill` read as "Get Mail" / "Facetime Video Call" / "Move"; marked `.accessibilityHidden(true)` (the adjacent title already labels each section). (`HomeView.swift`)
- **Group chat failed-send clobbered newer input** — on a failed send the old message text was restored unconditionally, overwriting anything typed during the in-flight request; now restored only if the field is still empty. (`GroupChatView.swift`)

#### iOS Simulator QA pass — round 2 (deferred-item fixes, email perf + security, tests)
- **Offline task captures were silently deleted instead of queued (data loss)** — `TaskCaptureService` rolls back (DELETES) tasks whose sync ends `.failed`, and `SupabaseSyncService` marked *every* sync error `.failed` — including offline, timeout, and unconfigured-backend. Now only a reached-server **rejection** marks `.failed`; `URLError` and `BackendClientError.backendNotConfigured` keep the task `.localOnly` so it survives and re-uploads on reconnect (`retryUnsyncedTasks` via `NetworkMonitor.onReconnect`). (`SupabaseSyncService.swift`)
- **Inbox star didn't change until a full reload** — `EmailService.toggleStar` now optimistically flips the Gmail `STARRED` label in the local thread cache, with rollback on failure, mirroring `markAsRead`/`markAsUnread`. (`EmailService.swift`)
- **AI chat showed the wrong tab context after relaunch** — `selectedTab` is restored from `@SceneStorage` without firing `onChange`, so `currentTab`/`previousNavigationTab` stayed `.home`. `MainTabView.onAppear` now seeds them from the restored tab. (`MainTabView.swift`)
- **Native "More" tab rendered pure black in dark mode** — the UIKit More list (Docs/Meetings overflow) painted `#000000` vs the app's `#1c1c1e`. Set an adaptive `UITableView` appearance background; the app has no other `UITableView` (SwiftUI `List` is UICollectionView-backed). (`TodosApp.swift`)
- **AI share sheet could present on the wrong window** — used `connectedScenes.first`; now selects the `foregroundActive` scene at both call sites. (`AIChatView.swift`)
- **CreateSheet email recipient placeholders looked prefilled** — email-shaped placeholders ("recipient@example.com") get auto-tinted blue by iOS data detectors; replaced with plain "Add recipients / Add Cc / Add Bcc" copy, matching `EmailComposeView`. (`CreateSheet.swift`)
- **Email date-parsing allocated formatters per message (perf)** — `EmailMessage.parseDate` and the thread receipt chip built `ISO8601DateFormatter`/`DateFormatter` on every decode / render; hoisted to cached `nonisolated(unsafe) static let` formatters (thread-safe for parsing once configured). (`EmailModels.swift`, `EmailThreadView.swift`)
- **Email-HTML render CSP hardened** — added `form-action 'none'; base-uri 'none'` to the WKWebView CSP (script execution was already blocked via `script-src 'none'`), closing a form-submission exfiltration vector in malicious email HTML. (`EmailThreadView.swift`)
- **Tests** — `EmailServiceTests`: `toggleStar` optimistic flip / unstar / rollback, and `parseDate` ISO-fractional / ISO-plain / RFC-2822 / invalid-fallback. `TaskCaptureServiceTests`: offline + unconfigured captures stay `.localOnly`, server-reject → `.failed`.

#### iOS email deep-dive (`/bug-hunt`, 4 parallel audit agents) — forward data loss + load race + detail-cache staleness
- **Forwarding an email sent only the snippet, not the body (data loss)** — the Forward action passed `lastMessage.plainText` (the `title`/snippet preview) as the body, so forwarded mail was silently truncated to a one-line preview. Forward now routes through `EmailDraft.isForward`/`originalMessage` with the **full** message body; the backend appends it as the quoted original (verified against `apps/server/.../google.ts`). (`EmailComposeView.swift`, `EmailThreadView.swift`)
- **A superseded inbox load could clobber a newer load's state** — `performLoadThreads` gen-gated only the spinner; a slow superseded load still wrote `threads`/`errorMessage`/`hasConnection`, flashing a stale error banner over freshly-loaded mail. Added a `loadGeneration == myGen` guard before state application and on every catch-block write. (`EmailService.swift`)
- **Opening a just-read / just-starred thread showed stale detail** — list mutations updated `threads` but not `threadDetailCache`, so the detail view showed the pre-mutation state until the cache TTL expired. Added `invalidateThreadDetail(ids:)`, called from `markAsRead` / `markAsUnread` / `toggleStar`. (`EmailService.swift`)
- **Tests** — `EmailServiceTests`: `tokenizeRecipients` (mixed `,`/`;`/whitespace separators, `Name <addr>` form, case-insensitive dedupe, empty/trailing) and `SenderIconRegistry.icon` (brand, subdomain→root, personal-provider→nil, multi-part TLD, case/whitespace, malformed). 24/24 green.
- Remaining email findings (avatar-pipeline perf, dead `EmailAIDraftSheet.swift`, copy-snippet, connectGmail re-verify) logged in `CODE_REVIEW_BACKLOG.md` → "Bug Hunt — 2026-06-08 — iOS email surface".

#### macOS Flow QA round — found via end-to-end code tracing of auth/email/chat/tasks/settings/voice flows
- **AI chat was limited to one message per launch (critical)** — `send()` guards on `streamingTask == nil`, but `finaliseStream` never cleared `streamingTask` on normal completion (only `cancelStream`'s drain did), so every message after the first was silently dropped. `send`/`retryMessage` now clear the slot at task end under a `cancelGeneration` guard (so a cancel-then-send can't be clobbered). (`MacAIChatService.swift`)
- **Local-model chat errors were a blank dead-end (critical)** — model-not-installed / inference-failed / runtime-unavailable set `errorMessage` (only shown on the empty state), leaving an empty assistant bubble with no retry mid-conversation. Now routed through `appendError(...)` so the error renders in the bubble and the retry row appears. (`MacAIChatService.swift`)
- **Tasks never synced to the backend during a normal online session (critical, data loss)** — the pending-mutation flush was wired only to `networkMonitor.onReconnect`, which never fires if the user is already online. Extracted `MacAppServices.flushPendingSync()` and now also run it on app launch and on `scenePhase == .active`. Detail-sheet `saveChanges` now marks the task `.pendingUpload` so edits to already-synced tasks actually upload. (`MacAppServices.swift`, `TodusMacApp.swift`, `MacTasksView.swift`)
- **Drafts folder showed wrong/empty results (high)** — `EmailSection.drafts` had the implicit raw value `"drafts"`, but the backend folder key is `"draft"` (singular) and bypassed the draft-listing path. Mapped `case drafts = "draft"` (matches iOS + `FOLDERS.DRAFT`). (`MacRootView.swift`)
- **AI chat history leaked across accounts on a shared Mac (high, privacy)** — conversations persist under a static, non-user-scoped Keychain key and were never cleared on sign-out. Added `MacAIChatService.resetForSignOut()` (clears in-memory state + overwrites the caches) and call it from `MacAppServices.signOut()`. (`MacAIChatService.swift`, `MacAppServices.swift`)
- **Folder switch left the previous folder's thread open (medium)** — the inbox view is reused across folder changes; added `.onChange(of: folder)` to clear `selectedThreadId`/`selectedSenderEmail`. (`MacEmailInboxView.swift`)
- **AI tool/calendar due dates with millisecond precision were silently dropped (medium)** — task/event date parsing used the default `ISO8601DateFormatter` (rejects fractional seconds). Added a shared `parseISODate` (fractional → plain) used at all live parse sites. (`MacAIChatService.swift`)
- **Compose body editor: missing placeholder, focus stealing, per-keystroke full rebuild (medium)** — `MacMarkdownBodyEditor` now renders a placeholder while empty, grabs first responder only on the rising edge of `isFocused`, and restyles attributes in place (preserves cursor + native undo, drops the O(n) rebuild). (`MacMarkdownBodyEditor.swift`)
- **macOS resize cursors + scroll-style walk + voice polish** — window-corner cursors now use the macOS 15 `NSCursor.frameResize` diagonal cursors (was `crosshair`); the side-pane divider uses `MacTheme.cardBorder`; `MacScrollStyle.applyToScrollableViews` got a 32-level depth cap; voice "speaking" rings now breathe. (`MacRootView.swift`, `MacScrollStyle.swift`, `MacVoiceChatPanel.swift`)

#### macOS Flow QA round 2 — remaining-issue fixes + deeper hunt (Meetings/Docs/GroupChat/Sharing/Search/Widgets/Calendar-edit)
- **Calendar grid edit/delete always 404'd (critical)** — `legacyCalendarEvent` used the composite `apple:`/`google:` id; `EKEventStore.event(withIdentifier:)` never matches a prefixed id, so every in-grid edit/delete failed. Now uses the raw `providerEventId`. (`UnifiedCalendarService.swift`)
- **Generative-UI cards could crash on a cyclic spec (critical)** — `ChatUISpecView.renderElement` recursed into children with no guard; untrusted model output with a cycle stack-overflowed. Added a depth limit (`renderElement(id:depth:)`, cap 24). (`ChatUISpecView.swift`)
- **Multi-account "From" picker didn't change the sending account (high)** — macOS sent `connectionId`, but `mail.send`'s schema only has `fromEmail` (the `connectionId` was silently dropped). Added `EmailDraft.fromEmail`, set it from the picked connection on send, and send it from both `EmailService.sendEmail` and `MacDraftService`. (`EmailModels.swift`, `MacEmailComposeView.swift`, `EmailService.swift`, `MacDraftService.swift`)
- **Local model not-downloaded triggered a silent multi-GB download mid-chat (high)** — added a `runtime.isReady(for:)` gate before local streaming; surfaces "open Settings → Local Models" instead of an indefinite "thinking" hang. (`MacAIChatService.swift`)
- **AI `update_task`/`delete_task` reported success on a missing task (medium)** — `applyUpdateTask`/`applyDeleteTask` now return Bool; the tool result is "Task not found" when the id doesn't match. (`MacAIChatService.swift`)
- **Star gave no feedback (medium)** — `toggleStar` is now optimistic (toggles the `STARRED` label immediately) with rollback on failure. (`EmailService.swift`)
- **Email attachments were never shown (medium)** — the thread view now renders attachment chips (filename + type + size), mirroring iOS. Display only; tapping-to-download needs a backend fetch endpoint. (`MacEmailThreadView.swift`)
- **Switching chat history discarded an unsaved live conversation (medium)** — `loadConversation` now saves the current unsaved chat first, mirroring `clearHistory`. (`MacAIChatService.swift`)
- **Calendar "Grant Access" was a dead no-op once denied (medium)** — when status is `.denied` the button now opens System Settings → Privacy → Calendars. (`MacCalendarView.swift`)
- **Switching docs leaked editor state across docs (high)** — added `.id(id)` to the editor pane so it recreates per doc (no stale Saved/Save-failed badge or word counts, no Retry writing to the wrong doc). (`MacDocsShellView.swift`)
- **Meeting detail blanked to "not found" on a transient refetch error (high)** — `loadMeeting` now only overwrites on a successful fetch. (`MacMeetingDetailView.swift`)
- **Widget deep links did nothing + widgets went stale (high)** — `todus://tasks|today|email` now route (navigation-only); widgets also refresh on `scenePhase == .inactive` (a windowed macOS app rarely hits `.background`). (`TodusMacApp.swift`)
- **Relocated a concurrent broken helper** — `ownedAddressesForReplyAll()` (added by other in-flight work) was placed inside `MacMailAssistantCard`, which has no `@Environment services`, yet it uses `services` and is called from `MacEmailThreadView`; moved it into `MacEmailThreadView` so the module compiles. (`MacEmailThreadView.swift`)

#### macOS Flow QA round 3 — remaining-issue fixes + launch-crash fix
- **App crashed on every launch (critical)** — `TaskSyncService.retryUnsyncedTasks` ran a compound `||` string-equality `#Predicate` fetch that traps inside SwiftData (EXC_BREAKPOINT). It now runs at launch/foreground via `flushPendingSync`, so the app SIGTRAP'd on startup. Switched to fetch-all + in-memory filter. (`TaskSyncService.swift`)
- **Widget "Complete task" button was a no-op stub (critical)** — `CompleteTaskIntent` now queues the id via the App Group, optimistically drops it from the snapshot, and reloads timelines; the main app drains the queue on launch/foreground (`MacAppServices.drainWidgetTaskCompletions`) to mark the task done + sync. (`CompleteTaskIntent.swift`, `WidgetSnapshotStore.swift`, `MacAppServices.swift`, `TodusMacApp.swift`)
- **Calendar & Smart-Insight widgets were always empty (high)** — `MacWidgetUpdateManager` never wrote `calendar`/`insight` (so Daily Overview "next event" was permanently "Clear schedule"). Now fetches upcoming events, packs colors, writes a calendar snapshot + a derived insight, and uses the atomic `updateSnapshot`. (`MacWidgetUpdateManager.swift`)
- **Shared conversations with structured content failed to open (high)** — `ShareGetResponse.messages` was typed `[[String:String]]`; any non-string `content` (Anthropic content blocks) failed the whole decode → "Link not available". Added a flexible JSON decode that flattens to display text. (`ShareConversationService.swift`)
- **Google (read-only) calendar events 404'd on edit (high)** — added `CalendarEvent.isWritable` (from the unified event); `openEditEvent` now shows the read-only summary for non-writable events instead of an editor that would 404. (`CalendarService.swift`, `UnifiedCalendarService.swift`, `MacCalendarView.swift`)
- **Sent emails arrived as raw markdown on one line (high)** — the compose body (plain markdown) was wrapped as `text/html` with no conversion. Added a conservative markdown→HTML converter (headings/bold/italic/quote/lists/links + `<br>`) applied in both send paths. macOS only for now (iOS shares the raw-body behavior). (`EmailService.swift`, `MacDraftService.swift`)
- **Automatic session-expiry sign-outs bypassed cleanup (medium)** — added `AuthService.onSignOut`; `MacAppServices` wires it so both manual and automatic sign-outs run the same per-user teardown (sync queues, email/AI caches, voice). (`AuthService.swift`, `MacAppServices.swift`)
- **Search showed stale calendar results after clearing the query (medium)** — clearing now restores the initial wide event window. (`MacSearchView.swift`)
- **Docs showed a blank white editor if its bundle was missing (medium)** — now loads a visible "Editor failed to load" state. (`TiptapDocEditorWebView.swift`)
- **Meetings calendar-sync failures were silent (medium)** — `syncFromCalendar` now sets `loadError` so the existing banner surfaces the failure. (`MeetingsService.swift`)
- _Not fixed (need backend / larger scope):_ subscription cancel still hardcodes `pro_monthly` (backend `getStatus` doesn't return the active product id); reminder scheduling, move-to-folder, compose-card CC/BCC input, notification cold-launch queue, and event-edit location/notes prefill remain (features / untestable here).

### Accessibility / UX
- **Billing credits display scale (iOS + macOS + web)** — credits now shown at 10× their internal dollar value so plans read as round, sensible numbers: Free **75**, Pro **150** (was Free 75 / Pro 15, which made the paid tier look smaller). Display-only `creditsDisplayScale`/`CREDITS_DISPLAY_SCALE = 10` applied in `formatCredits` so the usage meter matches the plan copy; actual billing/limits unchanged. Server truth: `model-pricing.ts` (Free 7.5, Pro 15). (`BillingSettingsView.swift`, `MacSettingsView.swift`, web `billing/page.tsx`)
- **iOS VoiceOver labels** — added accessibility labels to icon-only controls: AI chat voice + settings buttons, GroupChat send, CalendarAccounts visibility toggle + default-calendar star, and the Billing usage `ProgressView` (label + % value).
- **iOS keyboard handling** — Signatures editor gained a "Done" keyboard toolbar (was a trap on a List); compose recipient fields (To/Cc/Bcc) advance focus on return; global search submits on return and dismisses the keyboard on scroll.

### Added
- macOS DMG build script (`scripts/build-mac-dmg.sh`) — archives, signs, packages, and uploads to Cloudflare R2 with pre-flight safety checks
- `apps/macos/ExportOptions.plist` for Xcode Development-signed archive export
- `/downloads` page updated: Mac download button now serves DMG from Cloudflare R2 with internal tester guidance
- **macOS HuggingFace cache detection** — new `HuggingFaceCacheConnector` scans both the app's HF cache (`Documents/huggingface/models`) and the user's external cache (`~/.cache/huggingface/hub`) for MLX-shaped (`mlx-community/*`) model directories. Surfaces them in Settings → Local Models under a "Connected (HuggingFace)" section so users can adopt models they already pulled outside the app. Tapping "Use" routes the chat service through the MLX runtime via a synthesized `LocalModel` for uncurated repos (using the existing `MacAIChatService` routing path, alongside the Ollama tag heuristic).
- **Dedicated native auth session** — `/api/auth/mobile-token` now inserts a separate `session` row when handing off to iOS/macOS so the native app appears as its own "Active Session" in settings instead of inheriting the web OAuth session. Falls back to the web session token if the DB insert fails. (`apps/server/src/main.ts`)
- **Cross-platform settings sync** — `aiTone` (professional/casual/concise), `taskRemindersEnabled`, `calendarRemindersEnabled` moved from `@AppStorage`-only into `userSettingsSchema` so they sync across web/iOS/macOS via the existing settings tRPC route. (`apps/server/src/lib/schemas.ts`)
- **Web design system tokens** — explicit `--space-{xs,sm,md,lg,xl,2xl}` scale (4/8/12/16/24/32 px) matching iOS/macOS, plus `--surface-primary`, `--surface-secondary`, `--surface-sheet` aliases. Motion durations rebalanced: `--motion-duration-base` 220→250 ms, `--motion-duration-slow` 320→350 ms. (`apps/web/app/globals.css`)
- **Settings page polish** — `/settings/design-system` refactored to share the `_components-manifest.tsx` source of truth (377-line slimdown); `/settings/notifications` slimmed by ~160 lines using the new token aliases; `/settings/billing` + `/settings/ai` updated to use semantic surfaces; web `Button` component tightened for dark-mode contrast.
- **Playwright web parity capture** — new `scripts/parity/capture-web-playwright.mjs` headlessly captures gated screens (`/settings/design-system` etc.) using `PLAYWRIGHT_SESSION_TOKEN` cookies. Wired into `pnpm parity:screenshots:capture:web`.
- **Parity script surface filters** — `check-screenshots.mjs`, `capture-ios-deeplink.mjs`, `capture-ios-interactive.mjs`, `capture-macos-electron.mjs` all gained `--surface` / `--platform` / `--allow-missing` flags. The macOS capture script now builds + launches `apps/macos/TodusMac` via `xcodebuild` (Electron wrapper retired).

### Changed
- **iOS BillingSettingsView + DesignSystemView** — minor touch-ups for token consistency.
- **iOS / macOS contrast fix** — buttons no longer render white-on-white in dark mode.
- **iOS compose** — From picker, gray placeholders, heavier scrim in CreateSheet.
- **macOS Local Models UX** — (1) "Delete weights" now goes through a `confirmDestructive` dialog instead of nuking a multi-GB download on a single misclick; (2) an "Active" badge + "In use" (disabled) menu/buttons now show which local model the chat is using, with a `MacHaptic.levelChange` on selection (Recommended/Installed rows + Ollama + HuggingFace "Use" buttons); (3) the Download button is disabled with a tooltip + inline "Not enough free space · needs ~N GB" warning when the volume can't hold the weights (≈ download size + 2 GB headroom). (`apps/macos/TodusMac/Views/Settings/MacLocalModelsView.swift`)
- **macOS Live Voice panel** — a failed session now shows a "Try again" button (reconnects via the view model's `.failed`-allowed path) instead of stranding the user on a dead panel; the mute control is disabled until the voice view model exists. (`apps/macos/TodusMac/Views/Voice/MacVoiceChatPanel.swift`)

### Docs
- New canonical `AGENT_CONTEXT.md` — single source of truth for any agent landing in the repo (repo layout, feature map, doc map, recent work).
- `CLAUDE.md`, `AGENTS.md`, `APPS_ARCHITECTURE.md`, `SCRIPTS_GUIDE.md`, `GEMINI.md` re-synced — fixed stale `apps/mail` references in Web Frontend / Auth / Env sections, expanded iOS feature/services map (Docs / Meetings / Voice / Local AI), corrected tRPC router list, called out the legacy `pnpm build:frontend` / `pnpm deploy:frontend` script mismatch.
- New `FEATURES.md` per-surface feature catalog with clickable file paths, plus `FEATURE_TEST_PLAN.md` companion test checklist.
- `PROJECT_PLAN.md`, `PLANNING.md`, `ROADMAP.md` now carry "historical" banners pointing to the current canonical docs.

## [2026-05-24] Docs review round 3 — context-menu safety, sort menu rendering, macOS title autofocus

Follow-up round (3rd review pass — review-current-implementation, ux-polish, ux-assesment, bug-hunt).

**iOS:**
- iPhone context-menu Delete now routes through the same confirmation dialog as swipe-delete (long-press → Delete was equally fat-fingerable).
- Tap haptic only fires when open actually changes state (no buzz for re-tap on selected iPad row).
- Title save: `CancellationError` + `URLError.cancelled` swallowed — debounce cancel storm no longer flashes "Save failed".
- Retry button no-op fixed: reverting the title to the last persisted value clears the `.failed` badge (was stuck).
- Removed dead `.navigationDestination` from the iPad branch (sidebar drives detail via `selectedDocID`, never pushes a `String`).
- Rename `TextField` got `.submitLabel(.done)` + `.onSubmit` — Return now confirms.
- Title `TextField` got `.textInputAutocapitalization(.sentences)`.
- Star toolbar foreground: unstarred = `.secondary` (was `.accentColor`, read as "active").
- Dropped dead `savedRevertTask` `@State` (no longer assigned after persistent-saved badge change).
- Dropped dead `if shareURL != nil` guard — `effectiveAppURL` is non-optional.

**iOS WebView:**
- Hide-chrome CSS injection dedupes via `document.querySelector('style[data-todus-native-chrome]')` — SPA back/forward navigation no longer accumulates `<style>` nodes.

**Web:**
- `saveTitle` normalizes empty/whitespace-only titles to `"Untitled"` before mutate — prevents titles silently disappearing across platforms (matches iOS native shell).
- Divider between title and editor body wrapped in `data-doc-page-title` so native iOS shell's CSS hides it together with the title row (previously left an orphan horizontal rule above the editor body).

**macOS:**
- Format strip `Cmd+B` / `Cmd+I` shortcut bindings dropped — Tiptap already owns these inside the focused WebView; double-binding either doubled the toggle or stole keystrokes from the native title.
- `tiptapButton` gains `.help` + `.accessibilityLabel` + `.disabled(wk == nil)` so format buttons can't fire before editor loads.
- Sort menu rewritten with `Picker` + `.inline` style inside `Menu` — previous `Button` + sibling checkmark image didn't render the active state in macOS Menus.
- Sidebar starred row context menu: Star/Unstar label conditional on `d.isStarred` (was hardcoded "Unstar") + adds `Copy title` for 4-way menu parity.
- Table list context menu adds `Copy title`; row gets `.help` on long titles; `Updated` column uses `.relative(presentation: .named)` to match grid card format.
- `starredFirst` sort comparator simplified.
- `flushPendingSave` skips when the doc was removed from `allDocs` (delete just landed) — no wasted update for a 404'd id.
- `flushPendingSave` + `saveTitle` normalize empty/whitespace title to `"Untitled"` for cross-platform parity.
- `saveTitle` swallows `CancellationError` + `URLError.cancelled`, clears stale `.failed` badge on no-op.
- Title debounce 600ms → 500ms (matches iOS).
- **New:** `titleFocused` `@FocusState`; `load()` autofocuses title when doc opens empty/Untitled — Apple-Notes parity with iOS (this was UX assessment's #1 macOS gap).
- Star toolbar button: dynamic `.help` / `.accessibilityLabel` (Star ↔ Unstar), foreground yellow when starred / `.secondary` otherwise, `.disabled(doc == nil)`.
- Info popover button `.disabled(doc == nil)`.
- Dropped dead `savedRevertTask` `@State`.

**Items deferred to backlog** (architectural / broader UX work):
- iOS body autofocus after title submit (needs JS bridge to Tiptap)
- macOS `Cmd+K` quick-open / global search persisted across views
- Clickable star on macOS cards/rows (broader interaction redesign)
- Info popover field divergence iOS↔macOS (Created/Updated vs Words/Chars)
- macOS `Cmd+W` to close editor (back chevron works today)
- Recursive `AnyView(Group)` outline → `OutlineGroup` refactor
- Recursive doc tree cycle guard

## [2026-05-24] Docs review pass — UX polish, context menu parity, persistent saved badge

Follow-up to the docs overhaul, driven by four review passes (review-current-implementation, ux-polish, ux-assesment, bug-hunt).

**iOS:**
- Web doc page now exposes `data-doc-page-title` + `data-doc-sidebar` attributes; iOS WKWebView CSS injection updated to actually match them (previous selectors were no-ops — duplicate title + double sidebar were visible on iPhone).
- Swipe-delete on iPhone now requires a `.confirmationDialog` confirmation — fat-finger no longer destroys data.
- Recent section excludes docs already in Starred to stop the same row appearing 3× in the same List.
- Compound `.id("recent-…")` / `.id("starred-…")` on flat rows so SwiftUI doesn't merge swipe/hover state between section appearances.
- iPad row highlight restored — active doc gets `Color.accentColor.opacity(0.12)` `listRowBackground` (was lost when `List(selection:)` was removed in the nav fix).
- Haptics on open / create / delete / star / rename, success + error.
- Rename alert Save button disabled when trimmed text empty; renameText cleared on dismiss.
- `.id(doc.id)` on `DocEditorView` at both entry points — switching docs no longer briefly shows the previous doc's title.
- Autofocus moved from `DispatchQueue.main.asyncAfter` to a cancellable `Task` stored in `@State`; cancelled in `flushPendingSave` to stop focus firing on torn-down views.
- `flushPendingSave` also cancels `savedRevertTask` + `autofocusTask` to avoid orphan timers writing to `@State`.
- Save indicator wrapped in `.frame(minWidth: 70, alignment: .trailing)` so the title edge doesn't shift on every keystroke.
- Share button gated on `shareURL != nil`.
- Dark-mode injection now listens for appearance changes (was one-shot at load).
- MoreSheet 'Docs' entry no longer pushes via NavigationLink (double-stacked Docs' own NavigationStack inside MoreSheet's); now uses `onNavigate(.docs)` + `dismiss()`, mirroring Calendar.

**macOS:**
- Context menu parity with iOS across **all** doc surfaces (sidebar outline rows, starred rows, doc cards, table list rows): Open / Rename / Star / Copy title / Delete with confirmation. Previously only Open + Copy title — there was literally no way to delete a doc from the macOS UI.
- `MacDocsService` gains `renameDoc(id:title:)` and `togglePin(id:)` wrappers mirroring iOS so callers don't construct full `DocUpdateInput` for the common cases.
- Removed inline per-workspace "New document" sidebar button — used `try?` + silently swallowed errors, and was the 4th create entry point. Header `+`, All-docs toolbar `+`, and Cmd+N cover it.
- Sidebar outline indentation now uses `.padding(.leading)` instead of literal whitespace (works with dynamic type + screen readers).
- Star indicator + `.help` tooltip added to sidebar rows; cards gain `.help` on long titles.
- Cmd+B / Cmd+I keyboard shortcuts in the format strip; `.help` + `.accessibilityLabel` on every format button via the new `tiptapButton(_:_:help:shortcut:)` signature.
- All-docs grid: sort-mode change animates via `Motion.base` so reorder transitions instead of snapping.

**Both platforms — persistent saved badge:**
- `markSaved` no longer auto-reverts to `.idle` after 2 seconds on iOS or macOS. The Saved checkmark stays visible until the next `.saving` transition — trust signal matches Google Docs' "All changes saved in Drive". The fade-out was a confidence regression.

**Pre-existing bug-hunt items deferred to backlog** (added to `CODE_REVIEW_BACKLOG.md`):
- Recursive `AnyView(Group)` outline pattern breaks SwiftUI identity / animation
- Recursive `docRow` / `docOutline` has no cycle protection against corrupt server data
- Debounce title save + flushPendingSave can theoretically race two requests
- `commitRename` fire-and-forget Task isn't owned by the view
- macOS no Cmd+F to focus search; macOS search disappears when editing; AI revert button parity gap on iOS; iOS no body autofocus after title submit; iOS no grid view; iOS no sort menu

## [2026-05-24] Docs feature overhaul — iOS bug fixes + Apple-Notes / Google-Docs polish (iOS + macOS)

**iOS bug fixes (critical, unblocks users):**
- Fix: tapping a doc row on iPhone now opens the editor. Root cause was `List(selection:)` on a `NavigationStack` swallowing taps before `NavigationLink` could push (selection is iPad-only). iPhone now uses `NavigationStack(path:)` with explicit `NavigationPath`; rows are buttons that push via `path.append(id)` (iPhone) or set `selectedDocID` (iPad).
- Fix: `+` button on iPhone now creates **and** opens the new doc. Previously it only mutated `selectedDocID`, which iPhone's stack does not observe — the doc was created on the server but the user stayed on the list.
- `MainTabView` no longer wraps `DocsListView` in an outer `NavigationStack` (the list owns its own nav via size-class branch; double-stacking was silently swallowing pushes).

**iOS polish (Apple-Notes feel):**
- Native title `TextField` with debounced (500ms) autosave + save indicator (idle / saving / saved / failed-with-retry). Mirrors `MacDocEditorPane` shell pattern.
- Title autofocuses on newly-created docs (empty / "Untitled") so the user can start typing immediately.
- `.searchable()` filters by title + `contentText`. Workspace sections hide during active search; flat "Results" section appears instead.
- New "Recent" (top 5 by `updatedAt`) and "Starred" sections in the list.
- Flat row variant shows a one-line content preview.
- Doc info sheet (created / updated / ID) + share link + copy title in `…` menu.
- Title save debounce now snapshots `titleDraft` at schedule time so a teardown-time flush can't race against the scheduled task.

**macOS polish (Google-Docs feel):**
- Persistent sidebar — sidebar is always visible in an `HSplitView`; right pane swaps between `MacDocsAllPane` (no doc selected) and `MacDocEditorPane` (doc selected). Previously the sidebar disappeared during edit.
- `Cmd+N` creates and opens a new doc from anywhere in the docs view (hidden `Button` + `.keyboardShortcut`).
- Sidebar entries (workspace outline rows, starred rows, "All documents") get a `MacTheme.accent.opacity(0.16)` fill when their target matches `selectedDocId`.
- New sort menu (Most recent / Alphabetical / Starred first) in the All-docs header, persisted via `@AppStorage`.
- Richer doc cards: 15pt semibold title with inline emoji, 12pt secondary preview (falls back to "Empty document"), 10pt muted relative timestamp, top-right yellow star, hover scale (1.01) via `Motion.fast`, selected accent border (1.5px).
- Skeleton loading state: 6 redacted cards in the same grid layout instead of a bare spinner.
- "New document" / "No documents yet" copy aligned with iOS (was "New page" / "No pages yet").

**Cross-platform consistency:**
- Title autosave debounce aligned to 500ms iOS↔macOS.
- One canonical term: "New document" everywhere (was mixed with "New page").
- Empty-state copy unified.

**Architecture notes:**
- iOS editor body still uses the `DocsBrowserView` WKWebView (loads `/mail/docs/<id>` from the web app). Bundling the Tiptap editor into iOS for offline parity is a deferred follow-up project documented in the spec.
- Web page's title row is hidden via injected CSS in `DocsWebView` so it doesn't duplicate the native iOS title. Selectors are forward-looking — harmless no-op if the web template doesn't expose them yet.
- Five pre-existing docs bugs (force unwraps in `MacDocEditorPane` AI revert, `WKNavigationDelegate` weak-self gaps, leaked `Task.sleep` timers, silent flush errors, Personal-workspace auto-create races) flagged in `CODE_REVIEW_BACKLOG.md` for follow-up.

**Files touched:**
- `apps/ios/Todus/Todus/Features/Docs/DocsListView.swift` (rewrite)
- `apps/ios/Todus/Todus/Features/Docs/DocEditorView.swift` (rewrite)
- `apps/ios/Todus/Todus/Features/Docs/DocsWebView.swift` (CSS injection)
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift` (drop outer NavigationStack)
- `apps/macos/TodusMac/Views/Docs/MacDocsShellView.swift` (layout refactor + sidebar selected state + sort menu + DocCardView + skeleton)
- `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift` (pre-existing EdgeInsets + type-checker fixes to unblock build verification)
- `CODE_REVIEW_BACKLOG.md` (5 follow-up entries)
- `TASK.md`
- Specs / plans: `docs/superpowers/specs/2026-05-24-docs-feature-overhaul-design.md`, `docs/superpowers/plans/2026-05-24-docs-feature-overhaul.md`

---

## [2026-05-24] Settings cross-platform parity audit — macOS visual polish + AI sheet, web notifications fix, multi-platform sync

Full Settings gap analysis and implementation across macOS, iOS, and web.

**Backend schema** (`apps/server/src/lib/schemas.ts`):
- Added `aiTone: z.enum(['professional','casual','concise'])` — was `@AppStorage`-only on iOS/macOS, now synced
- Added `taskRemindersEnabled: z.boolean()` and `calendarRemindersEnabled: z.boolean()` — same, now synced

**macOS Settings** (`MacTheme.swift`, `MacSettingsView.swift`, new `MacAISettingsView.swift`):
- Spacing tokens: `settingsRowVerticalPadding` 11→13, `settingsSectionSpacing` 28→32, new `settingsSubgroupSpacing = 16`
- Avatar: 36pt → 44pt (matches iOS baseline)
- Account card: "Delete account" removed from top card → moved to new **Danger Zone** section at bottom (matches iOS pattern)
- AI Assistant section: 30-item monolithic wall replaced by a single nav row → opens in a dedicated `MacAISettingsView` sheet with proper sub-grouping (Permissions / Personalization / Mail Assistant with 7 sub-groups / Model)
- Connected Services: refactored from legacy single-Gmail row → dynamic multi-account list via `connectionsService.connections` + "Add Gmail account" row
- Active Sessions: row padding 8→10, header font 10.5→11, value font 11.5→12, "This device" accent badge
- Notifications: `taskRemindersEnabled` / `calendarRemindersEnabled` now sync to backend via `syncSetting`
- `aiTone` now syncs to backend via `syncSetting`

**iOS Settings** (`SettingsView.swift`):
- `SettingsSyncModifier` extended: `taskRemindersEnabled`, `calendarRemindersEnabled`, `aiTonePreference` now call `syncSetting` on change

**Web** (`settings/notifications/page.tsx`, `settings/ai/page.tsx`):
- Notifications page fully rewritten: broken preview-only form (with nonexistent backend fields) replaced with working `taskRemindersEnabled` / `calendarRemindersEnabled` toggles wired to `trpc.settings.save`
- AI page: Response Tone `SelectRow` (Professional / Casual / Concise) added to Personalization section, wired to new `aiTone` backend key

## [2026-05-24] Design system alignment pass — accent canonicalization, motion + spacing tokens, macOS contrast fixes, screenshot infra

Cross-platform alignment pass closing 6 tracked gaps in `DESIGN_SYSTEM_INCONSISTENCIES.md`. iOS adopted as canonical reference (visually cleanest per user direction). Five parallel slices:

- **Accent palette canonicalized to muted "refined editorial" values.** iOS shipped TWO different accent systems (legacy `accentColor(for:)` function with muted hex `#3873d9`, and the new `AppTheme.Accents` enum with vibrant `#407AFF`). Legacy function deleted; `AppTheme.Accents` updated to canonical muted RGB: blue(0.22,0.45,0.85) indigo(0.35,0.32,0.78) teal(0.18,0.52,0.55) green(0.25,0.55,0.32) orange(0.78,0.48,0.18) rose(0.72,0.28,0.35). Single source of truth. macOS dark-mode brightening normalized to consistent ~7-8% across all 6 colors (was inconsistent 6-17%). Web `ACCENT_COLORS` already at canonical hex.
- **macOS pill contrast + motion easing fix.** Segmented selected pill dark `white: 0.22 → 0.30` — lifts visibly above track (`0.15`) instead of barely separating. `Motion.fast` switched from `.easeOut` to `.snappy(0.15)` and `Motion.slow` from `.snappy` to `.spring(0.35, 0.85)` so motion feel matches iOS. Added missing `sheetBackground` (light 0.978 / dark 0.135) and `surfaceSecondary` (light 0.96 / dark 0.205) tokens — were referenced by intent across mac code but had no canonical token.
- **Web motion duration alignment.** `--motion-duration-base: 220ms → 250ms` and `--motion-duration-slow: 320ms → 350ms` to match iOS `Motion.base` / `slow`. `fast: 150ms` already matched.
- **Web spacing tokens (4 / 8 grid)** — `apps/web/app/globals.css`. New `--space-xs / sm / md / lg / xl / 2xl` (4 / 8 / 12 / 16 / 24 / 32 px) on `:root`, exposed via Tailwind v4 `@theme inline` as `--spacing-*` so `p-md`, `gap-xl`, `mt-2xl` work. Mirrors iOS `Spacing` / macOS `MacTheme.spacing*` scale. Plus semantic surface aliases `--surface-primary / -secondary / -sheet` alongside shadcn's `--card / --accent / --popover` for cross-platform naming clarity. Light-mode parity audit complete — web `:root` runs ~2% lighter than iOS canonical with intentional cool tint from shadcn lineage; documented and accepted in `DESIGN_SYSTEM_INCONSISTENCIES.md`.
- **Screenshot regression infrastructure for DS viewers** — `scripts/parity/capture-web-playwright.mjs` (new, headless Playwright via the existing `packages/testing` install — no new dep added), `capture-macos-electron.mjs` rewritten for the native `TodusMac` SwiftUI shell (the old Electron path was dead), manifest extended with 7 DS slugs + `macos` platform, `--surface` / `--platform` / `--allow-missing` filters on `check-screenshots.mjs`. Capture commands: `pnpm parity:screenshots:capture:{web,ios,macos:auto} -- --surface design-system`. Three blockers documented (web auth tokens not in CI, iOS deep-link router missing `/settings/*`, macOS DS sidebar not deep-linkable) — infra ready, baselines deferred until those land. No pixel diff yet (presence-only check); `pixelmatch`/`odiff` is the natural next step.

Also resolved in this pass (not visually impactful but tracked):
- **Naming aliases on web** — `--surface-primary` etc. give cross-platform readers a shared vocab without breaking shadcn names.
- **Web outline button parity** — `outline` variant dropped opaque `bg-background` for `bg-transparent` so it reads correctly over card surfaces, matching iOS / macOS.

**Two new tracked followups** (not blocking this pass):
- iOS still has dual accent stores (`@AppStorage("ios_accent_color")` synced to backend + `services.accentPreference` local-only). Both render canonical palette now but don't cross-update. Recommend consolidating around the backend-synced path.
- iOS typography not centralized like macOS — `.font(.system(...))` literals scatter across views. macOS centralizes via `cardTitleFont` / `metaFont` etc. Worth porting.

Validation: `xcodebuild` succeeded on both Todus (iOS) and TodusMac (macOS); `oxlint --deny-warnings` clean on touched web files; `tsc --noEmit` introduced zero new errors. iOS build has pre-existing errors in `AppServices.swift:940-956` (parallel session work on `syncSetting` / `OneFieldInput` — unrelated to this pass).

## [2026-05-24] Web design system — Liquid Glass button + manifest-driven DS viewer

Closes two yellow gaps in `DESIGN_SYSTEM_INCONSISTENCIES.md`:

- **`Button variant="glass"`** (`apps/web/components/ui/button.tsx`) — sister of iOS `LiquidGlassButtonStyle`. Backdrop-blur + saturation, hairline white border (10% in dark, 20% in light), layered shadow, press = scale 0.97 + brightness lift. Default radius uses `--radius-md` (14px) so corners match iOS `Radius.control`. Transitions use the existing `--motion-duration-fast` + `--motion-easing-standard` tokens.
- **Outline button is transparent again.** `outline` variant dropped `bg-background` → `bg-transparent` so it stops reading as a filled chip on top of card surfaces. Hover still tints with `bg-accent`. Matches iOS / macOS outline buttons.
- **DS viewer is manifest-driven.** New `_components-manifest.tsx` exports a typed `COMPONENT_MANIFEST` (name, category, file, variants/render, optional notes). The viewer maps over it grouped by category (buttons / forms / layout / feedback / overlays / navigation). Each entry shows its source file path; a dashed callout at the bottom points the next contributor at the manifest. Glass button renders over a soft gradient stage so the backdrop-blur is visible.
- **Validation** — `npx oxlint --deny-warnings` clean on the three touched files; `npx tsc --noEmit` introduced zero new errors (the pre-existing 25 errors live in unrelated files: editor, mail composer, settings forms).

## [2026-05-21] macOS build gate fixes for Home and Settings

- **Home dashboard compile fix** — Kept `HoverableRow` nested inside `MacHomeView` and restored the correct enclosing brace placement after the helper, fixing the Swift syntax error that stopped the macOS build.
- **Settings compiler complexity fix** — Moved the dynamic single-field settings encoder out of `MacAppServices.syncSetting` because Swift 6 rejects nested generic types in generic functions. Split `MacSettingsView` into smaller layout, sync, lifecycle, and dialog helper chains so SwiftUI type-checking completes reliably.
- **Validation** — `xcodebuild -project apps/macos/TodusMac.xcodeproj -scheme TodusMac build` now succeeds. Existing `MacVoiceChatPanel.swift` `nonisolated(unsafe)` warnings remain.

## [2026-05-21] Landing page tier-2 polish: real-component demos, darker chat panel, native section removed

User feedback on the first landing-page expansion: the inline CSS mockups looked nested-card-y and off-brand, the AI chat panel was too light, the native-app section's copy ("Built native, not wrapped. Real Swift apps...") read like AI marketing speak. This pass:

- **`NativeAppSection` removed.** Deleted from `components/home/product-sections.tsx` exports and from `HomeContent.tsx`. The downloads page (`/downloads`) already covers platforms.
- **Feature demos rewritten to mirror the real app.** `product-sections.tsx` now copies the visual blueprint of the real components (`apps/web/components/calendar/calendar-grid.tsx`, `apps/web/app/(routes)/mail/tasks/page.tsx`, `apps/web/app/(routes)/mail/meetings/page.tsx`, `apps/web/components/docs/`). Single outer frame per demo (no nested cards). iOS blue `#007AFF`, system reds `#FF453A`, greens `#30D158`, yellows `#FFD60A` — matches the real app's accent palette. Each demo has scroll-triggered staggered reveals (event blocks fade in column-by-column, task cards drop in, meeting rows slide from the left, checklist items pop sequentially). Adds a live "now" line on the calendar demo.
- **Plain copy.** Replaced marketing speak. "Built native, not wrapped" → removed entirely. "Turn email into action" → "Pull tasks out of email. Drop them where they go." "Meetings, recorded and recapped" → "Meetings get transcribed and summarized." Removed "AI-generated" claims that the demos don't actually prove.
- **AI Chat section darkened.** In `HomeContent.tsx`: the inner chat panel `bg-[#252525]` → `bg-[#0E0E0E]` with `border border-white/[0.06]` + soft shadow. Pinned-conversations panel `bg-zinc-900 opacity-30` → `bg-[#0A0A0A] opacity-40` + hairline border. Chip backgrounds `bg-[#303030]` → `bg-[#181818]`. Edge fade gradients `neutral-800` → `#0E0E0E` so the row blends into the panel instead of standing off it.

## [2026-05-21] Landing page expansion: split CTA, product sections, native-app proof, FAQ page

Second polish pass on `apps/web` after the cleanup of YC badge / socials / contributors:

- **CTA split out of footer** — New `components/home/cta.tsx` (`CTASection`). Flat, no card, sits inside `max-w-7xl`. Removed the gradient/rounded card that previously wrapped the "Experience the Future of Email Today" headline + columns + legal line together. Rendered from `HomeContent.tsx` as a sibling of `<Footer />`, so other pages (about, terms, pricing, downloads, contact, FAQ, blog, compare) keep using the column-only footer without the CTA.
- **Footer flat + restructured columns** — Rewrote `components/home/footer.tsx`. Drops `bg-panelDark mx-1 ... rounded-xl`; now `border-t border-white/10 bg-transparent` sitting flat against the page. Columns: **Resources** (Privacy, Terms), **Product** (Download, Pricing, FAQ, Github), **Company** (About, Contact). Year is `new Date().getFullYear()`. Bottom row keeps About / Contact / Terms / Privacy as dividers.
- **Landing page product sections** — New `components/home/product-sections.tsx`. Exports `ProductSections` (Calendar, Tasks, Meetings, Docs) and `NativeAppSection`. Each feature row is text + an inline HTML/CSS mockup (no PNGs needed — placeholder illustrations match the page's design tokens). `NativeAppSection` includes a CSS iPhone frame (notch + inbox rows) and a CSS Mac window frame (traffic lights + 3-pane mail UI) with `Download for Mac` / `Get on iPhone` CTAs underneath. Wired into `HomeContent.tsx` between the existing feature grid and the footer.
- **New `/faq` page** — `app/(full-width)/faq.tsx` using the existing Radix `Accordion` primitive. 10 entries: the original 6 from the JSON-LD block plus 4 new ones (self-host, custom domains, Outlook ETA, data handling). Route registered in `app/routes.ts`; `/faq` added to the prerender list in `react-router.config.ts`.
- **JSON-LD parity** — `structuredData.faqPage.mainEntity` in `lib/site-config.ts` now ships the same 10 Q&A pairs the FAQ page renders, so Google rich snippets stay in lock-step with the visible content.

## [2026-05-21] Cross-platform design system pass: dark bg lift, motion tokens, accent palette, DS viewer + docs

First unified pass on tokens across `apps/web`, `apps/ios/Todus`, `apps/macos/TodusMac`. Five slices:

- **Dark mode background lifted to Apple system dark `#1c1c1e`** (`Color(white: 0.109)`) on iOS + macOS — previous iOS `#0C0C0C` and macOS `~#141414` were too inky vs reference. Surface tokens stepped in ~0.04–0.06 white increments to preserve hierarchy. Hardcoded `Color(white:)` literals across `MacSettingsView`, `MacCalendarView`, `MacAssistantPanel`, `SettingsView.swift:1758`, and `CalendarViewController.swift:55` refactored to token references so future bg sweeps stay in one place.
- **Motion tokens** — new `Motion.fast/.base/.slow` enums on `AppTheme.swift` (iOS) and `MacTheme.swift` (macOS); new `--motion-duration-fast/base/slow` + `--motion-easing-standard/emphasized` CSS custom properties on web (`apps/web/app/globals.css`). Replaced inline `.snappy(...)`, `.easeOut(...)`, `.easeInOut(...)`, `.spring(...)` durations across ~15 iOS callsites (CustomTabBar, BoardColumnView, BoardTaskCard, TaskRowView, TaskTableView, CalendarTabView, CalendarNavBar, CalendarListView, TabBarOnboardingView, TabBarCustomizationView, ToastOverlay), ~17 macOS callsites (MacSidebarView, MacRootView, MacAssistantPanel, MacCalendarView, MacToastOverlay, MacTasksView, all Email/Home/Voice/Meetings/Docs views), and 9 web shadcn/ui files (button, input, dialog, sheet, accordion, navigation-menu, nav-main, app-sidebar, sidebar). Dropdowns, panels, hover states, and tap feedback now share a tunable duration vocabulary; previously instant transitions on sidebars and menus animate smoothly.
- **iOS accent palette parity** — ported the 6-color accent system (blue / indigo / teal / green / orange / rose) from macOS + web to iOS. New `AppTheme.Accents` enum + `AccentPreference` stored on `AppServices` (UserDefaults-backed, default `.blue`). Picker row added to `AppearanceSettingsView`. Hardcoded `accentBlue` literals on `AuthView` and `StartupOnboardingView` swapped for `AppTheme.Accents.blue`.
- **Hidden Design System viewer on all three platforms**, gated to `TODUS_ALLOWLISTED_EMAILS` (Swift) / `VITE_TODUS_ALLOWLISTED_EMAILS` (web) allowlist:
  - Web: `/settings/design-system` (new route in `apps/web/app/(routes)/settings/design-system/page.tsx`). `clientLoader` redirects non-allowlisted users to `/settings/general`. Settings nav entry conditionally rendered. New `apps/web/lib/developer-access.ts` mirrors the Swift `TodusDeveloperAccess.isAllowlisted(email:)` pattern.
  - iOS: `Features/DesignSystem/DesignSystemView.swift` + `DSTokenRow.swift`. NavigationLink from `SettingsView` developer section, gated by `TodusDeveloperAccess.isAllowlisted`. Xcode project updated.
  - macOS: `Views/Settings/MacDesignSystemView.swift`. Sheet-presenting button in `MacSettingsView` under the existing developer-mode gate (which already requires allowlist). Pbxproj updated.
  - Each viewer renders: Colors (light + dark swatches with hex / token name), Accent palette, Typography (samples per scale), Radius (6-tier chips), Spacing (4 / 8 grid), Shadows (web), Components gallery (buttons, cards, badges, dropdowns, dialogs, sheets, etc.), Motion (live demo blocks animating `fast/base/slow`). Each section ends with a "How to change" callout pointing to the source-of-truth file + line range.
- **Documentation** — new `DESIGN_SYSTEM.md` (canonical token reference with cross-platform mapping table) and `DESIGN_SYSTEM_INCONSISTENCIES.md` (resolved + tracked gaps) at repo root. Design System section added to `CLAUDE.md`, `AGENTS.md`, and `APPS_ARCHITECTURE.md` so future agents know the system exists and where to update it.

Verified: `xcodebuild` builds succeeded on Todus (iOS) and TodusMac (macOS). `tsc --noEmit` + `oxlint --deny-warnings` clean on touched web files.

## [2026-05-21] Website polish + downloads page

Marketing site cleanup pass on `apps/web`:

- **Hero** — Removed the "Backed by Y Combinator" badge from the hero (`components/home/HomeContent.tsx`). Pulled YC mention from the meta description in `lib/site-config.ts` and the about-page meta in `app/(full-width)/about.tsx`.
- **Navbar** (`components/navigation.tsx`) — Removed the round logo crop and the "beta" badge under it; logo now renders at its natural aspect. Removed the Resources mega-menu (Twitter / LinkedIn / Discord). Added a "Download" link pointing to the new `/downloads` page on both desktop nav and mobile sheet. Removed the social-icon row from the mobile sheet.
- **Footer** (`components/home/footer.tsx`) — Full rewrite. Killed the gradient.svg background for a flat surface. Dropped the Product column. Removed SOC2 link (we don't have SOC2). Removed the Twitter / LinkedIn / Discord row. Year is now `new Date().getFullYear()` instead of hard-coded 2025. Tightened the "Experience the Future of Email Today" headline contrast (solid white) so it reads on the flat surface.
- **Global link cleanup** — Replaced every `github.com/todus-app` / `github.com/Mail-0/Zero` URL with `github.com/Ludvig-Hedin/Todus` across `apps/web`, `.github/CONTRIBUTING.md`, `.github/PULL_REQUEST_TEMPLATE.md`, `.github/TRANSLATION.md`, and `README.md`. The `nav-user` "Customer Support" link now points at GitHub Issues instead of Discord. Translation guide no longer mentions the (defunct) Discord server.
- **/contributors removed** — Route unregistered in `app/routes.ts` and dropped from the prerender list in `react-router.config.ts`. The old page file is left on disk but unrouted.
- **/downloads added** — New page at `app/(full-width)/downloads.tsx`, routed in `app/routes.ts` and added to the prerender list. Three cards: macOS desktop (GitHub releases), iPhone (App Store), and the web app (login button). No Android / Windows / browser-extension placeholders.
- **README rewrite** — Trimmed to a short overview + feature list + download pointer + quick-start. Self-hosting moved out to a new `SELF_HOSTING.md` at repo root. Star History section removed. Team / contributors footer removed.

## [2026-05-21] iOS — drop stale v1 inbox cache so new mail isn't pinned below stuck rows

After the sync recovery landed, returning iOS users saw fresh mail load correctly but ~30 legacy threads stayed pinned at the top of the inbox. Root cause: the v1 cache file (`email_inbox_threads_v1` in UserDefaults) was written while the backend's Gmail continuous sync was disabled, so some rows had a `latestReceivedOn` that had fallen back to `Date()` (now) inside `syncThread`'s date-normalization catch. Those rows now have a permanent future-ish date, which kept anchoring `currentNewest` ahead of every real incoming row and tripping the `isStaleRefresh` guard that keeps the cache when it looks newer than the network response.

- **Cache version bump v1 → v2** (`apps/ios/Todus/Todus/Services/Email/EmailService.swift`) — New `cacheDataKey` / `cacheTimestampKey` so the next launch starts from a clean cache built from the fresh backend response. Legacy v1 keys are explicitly removed on `init` and on `resetForSignOut` to avoid leaking orphaned bytes.
- **Sanity filter on cache load** (`apps/ios/Todus/Todus/Services/Email/EmailService.swift`) — `loadCachedThreads` now drops any thread with a date more than a day in the future or earlier than 2000-01-01. Belt-and-suspenders for future regressions that would otherwise re-stamp `Date()` into the cache and re-create the same symptom.

## [2026-05-21] Mail sync recovery: Gmail watch self-heal, getThread shard race fix, folder pagination

Native clients (iOS + macOS) were stuck on month-old mail with no new arrivals and "Failed to load thread." on tap. Root causes fixed:

- **`mail.rewatchGmail` mutation** (`apps/server/src/trpc/routes/mail.ts`) — Force-renews the Gmail PubSub watch + push subscription for the active connection. Gmail watches expire after ~7 days; the hourly cron renews any older than 5 days, but a connection whose watch was lost (subscription deleted, IAM blip, missed cron tick) gets stuck and continuous sync stops delivering new mail. Clears `gmail_sub_age` KV + enqueues `subscribe_queue` job. Idempotent (PubSub topic `Already Exists` is swallowed).
- **Backend auto-rewatch when inbox is stale** (`apps/server/src/trpc/routes/mail.ts`) — When `listThreads` sees an empty inbox or a newest-row older than 24h on a Google connection, it now also enqueues a subscribe job alongside the existing resync trigger. Self-heals the "stuck watch" state on the user's next list call without any client-side action.
- **Composite-cursor pagination fix for folder queries** (`apps/server/src/routes/agent/db/index.ts`) — `findThreadsByFolderWithPagination` was still comparing the raw page-token to `latestReceivedOn` lexically. After the d8d471c7 token-format change (JSON `{ latestReceivedOn, id }`), `{` > `2` made `lt` true for every row, so page 2 returned the same newest slice forever. Now reuses `buildPaginationConditions` like the all-threads path.
- **`getThread` shard race no longer picks empty stubs** (`apps/server/src/lib/server-utils.ts`) — `ZeroDriver.getThreadFromDB` returns a truthy `{ messages: [], latest: undefined }` placeholder for shards that don't own the thread (and kicks off an async re-sync in the background). The previous race-success condition `if (thread)` was making `Effect.raceAll` declare the empty shard the winner whenever it resolved first, so users whose thread lived in a later shard hit "Failed to load thread.". Race now only succeeds when the result actually has a message payload.
- **iOS — proactive Gmail rewatch on stale refresh** (`apps/ios/Todus/Todus/Services/Email/EmailService.swift`) — Refresh path now triggers `mail.rewatchGmail` when the displayed inbox / incoming slice is older than 24h, or when both are empty. 6-hour cooldown to avoid flooding `subscribe_queue` on repeat refreshes within the same session. Cleared on sign-out.
- **iOS — surface real backend error on thread tap** (`apps/ios/Todus/Todus/Services/Email/EmailService.swift`) — `friendlyThreadLoadMessage` now parses the tRPC error envelope `{ error: { json: { message } } }` and surfaces the actual server message (e.g. "Thread <id> not found") for 5xx responses instead of the generic "Mail service is unavailable.". Makes silent shard misses diagnosable from the UI.
- **macOS — mirrored rewatch + error parsing** (`apps/macos/TodusMac/Services/Email/EmailService.swift`) — Same proactive `mail.rewatchGmail` trigger on stale refreshes. `loadThread` now uses the same `friendlyThreadLoadMessage` + `parseTRPCErrorMessage` pipeline so the desktop app surfaces backend errors instead of a flat "Failed to load thread.".

## [2026-05-21] iOS UX pass: retire default-mail onboarding, tighten Tasks header, smarter briefing, thread-fetch timeouts

- **Onboarding** — Removed the "Make Todus your mail app" step (`apps/ios/Todus/Todus/App/RootView.swift`). iOS still has no public API to set a default mail app, so the step couldn't function; onboarding total is now 3 steps. The `DefaultMailOnboardingView.swift` file is left in place (dead code) plus the `hasConfiguredDefaultMailPrompt` flag stays as a no-op stored preference so migration/sign-out reset paths keep compiling.
- **Tasks header** — Removed the green "All clear" header chip; tightened search-bar vertical padding (4→2pt); raised the inset between the pinned search bar and view content from 6→18pt across all four view modes (List / Board / Table / Dates) so spacing is consistent at the 16–24px target. Smart-sort bucket headers (e.g. "No date") are now rendered as inline list rows instead of `Section` headers, so they scroll with content instead of sticking to the top.
- **Tasks Board** — Wrapped `BoardView` in a `GeometryReader` and pinned each column to the available scroll height. Horizontal `ScrollView`s don't propagate vertical bounds to `.frame(maxHeight: .infinity)` content, which previously made columns vertical-center inside the viewport — producing a huge blank gap above the column headers.
- **Home Assistant Briefing — fewer false positives** — Receipts from senders that don't look automated (e.g. `support@openrouter.ai`) were being classified as `needs_reply`, producing bogus "URGENT REPLY" cards for $2 invoices. Tightened `classifyThreadKind` so strong receipt phrases ("tax invoice", "amount paid", "your purchase", "transaction details", "subscription renewed", …) always classify as `receipt` regardless of sender automation status. Expanded `NOREPLY_SENDER_PATTERN` to include `billing@`, `payments@`, `receipts@`, `invoices@`, `subscriptions@`, `orders@`, `accounts@`, `mailer-daemon`, `postmaster`. `replyNeeded` and `deadline_risk` loops are now gated by `!isNonConversational` so receipts / notifications / marketing / verification threads never produce urgent-reply loops.
- **Home Assistant Briefing — visual** — Fixed-width (72pt) badge pills on the briefing feed rows so the row title text starts at the same x-offset regardless of badge label length, plus a subtle stroke outline on the badge for legibility.
- **Email thread load timeouts** — `mail.get` server route now races the `getThread` shard fetch against a 15s timeout and surfaces `INTERNAL_SERVER_ERROR` instead of letting the request hang to the Cloudflare outer limit. iOS `EmailService.loadThread` adds a parallel 20s watchdog that cancels the in-flight request and surfaces typed error messages ("Thread is taking too long to load. Pull to retry." / "You're offline." / "Mail service is unavailable.") instead of a generic "Failed to load thread.". Eliminates the ≈90s "loading forever" experience when a shard or Gmail subrequest stalls.

## [2026-05-20] iOS ship-readiness pass: DI seams, all skipped tests activated, UI test target, voice mic lock, autosave migration, debounced policy push

Third pass closes the "complete after small fixes" gaps from the 2026-05-17 review. **67 unit tests pass, 0 fail, 0 skipped** (was 66 / 0 / 15). UI test target compiles. All recommended hardening from the strict review landed.

**Tests — zero skipped**
- All 15 previously-skipped tests now active and passing, plus 1 new test (pagination dedup no-op when incoming is older). DI seams added without changing any public API:
  - `AuthService`: `AuthTransport` protocol + `URLSession` conformance; `classifyCallbackTokens` extracted from `completeAuthentication`; `beginPendingAuthFlow`/`endPendingAuthFlow`/`isPendingAuthFlowActive` helpers extracted from `signInWithGoogle`.
  - `TodosAPIClient`: internal init with custom `URLSessionConfiguration` injection.
  - `AIChatService`: `classifyFlushDecision` nonisolated static helper extracted from `flushTokenBuffer`.
  - `EmailService`: `mergePages` static helper extracted from `performLoadThreads`.
  - `NetworkMonitor`: `PathProviding` protocol + `NWPathProvider` default impl + internal init.
  - `RemoteFirstTaskParsingService`: `RemoteTaskParsingTransport` protocol + internal init.
  - `AppleRemindersSyncService`: `EKReminderStoring` protocol + internal init; test-only readbacks (`_test_inFlightUpserts`, `_test_coalescedRetryCount`, `_test_recordPendingUpsert`).
- All new init params have defaults pointing at real implementations; existing call sites untouched.

**UI test target stood up**
- `TodusUITests` target wired (xcodegen). `--ui-testing` launch-arg detected in `AppServices.init` injects fake bearer + onboarding flags + `hasReachedMainTab` so XCUITests skip auth and land on MainTab deterministically. Startup network calls (`refreshSession`, AI snapshot fetches, shared profile load) gated behind `!isUITestingMode`.
- 3 test files in `TodusUITests/`: `TodusUITests.swift` (smoke), `CriticalFlowsTests.swift` (C1-C5 regression smoke via simulated deep link / notification / mutation pending state), `ParitySmokeTests.swift` (startup card on fresh install, voice settings accessibility, docs empty state, automation policy reachability).
- UI test target compiles clean (`xcodebuild build-for-testing`). UI test execution requires booted simulator (sandbox blocks here — verify with `xcodebuild test -only-testing:TodusUITests` locally).

**Voice race + autosave migration + policy debounce**
- **Voice mic lock** ([`Services/Voice/VoiceMicLock.swift`](apps/ios/Todus/Todus/Services/Voice/VoiceMicLock.swift)) — cooperative `@MainActor @Observable` lock with `acquire(owner:)` / `release(owner:)`. Wired into both `VoiceSessionCoordinator` (owner: "coordinator") and `VoiceChatViewModel` (owner: "modal"). Siri Shortcut + modal-open at the same time can't double-attach AVAudioEngine. Same class of bug as H17.
- **Compose autosave migration** ([`Features/Email/EmailComposeView.swift`](apps/ios/Todus/Todus/Features/Email/EmailComposeView.swift)) — `migrateLegacyAutosaveIfNeeded()` runs once on first restore: copies `reply.<threadId>` / `replyAll.<threadId>` UserDefaults blobs to the unified `compose.<threadId>` key (replyAll wins if both present), then deletes the legacy keys. Idempotent.
- **EmailAutomationPolicyView debounced push** — 300ms debounced `saveSharedAIProfile` per change instead of `onDisappear`-only. Crash mid-edit no longer strands changes. `.onDisappear` still flushes as fallback. `AssistantAutomationPolicy` + `AssistantQuietHours` + `AssistantAutoSendScenario` gained `Equatable` for `onChange(of:)`.

**Docs dedup + startup migration tightened**
- `DocsService.refresh()` no longer auto-creates a "Personal" workspace when the server already has one (case-insensitive name check). On 409/422 race, refetches and uses the server's existing workspace.
- `hasSeenStartupCard` migration: dropped unreliable `hasPersistedBearerToken` signal (Keychain survives uninstall on iOS — could silently skip card on fresh reinstall). Added new positive signal `Keys.hasReachedMainTab`, set in `MainTabView.onAppear` the first time the tab shell appears. Migration: card skipped only when `hasReachedMainTab` OR (`isAuthenticated && any prior onboarding flag`).

**Verification**
- `xcodebuild build` → **BUILD SUCCEEDED**
- `xcodebuild build-for-testing` → **TEST BUILD SUCCEEDED**
- `xcodebuild -only-testing:TodusTests test` → **TEST SUCCEEDED** (67 / 0 / 0)
- UI tests pending booted simulator (run locally).

**Manual follow-ups (user)**
1. Open Xcode + run UI tests on simulator/device.
2. AI conversation history + AppTheme avatar cache migrations run silently on first launch (transparent).
3. Activate Siri Shortcut "Start Voice Assistant" via Shortcuts app.
4. Apple `com.apple.developer.mail-client` entitlement still pending (pre-existing TODO).
5. Review + commit when ready.

## [2026-05-17] iOS parity sweep: voice + docs + automation + tests + startup card

Second pass on iOS (after morning bug-hunt + ux-polish): closed remaining macOS→iOS parity gaps and stood up a real test suite. 5 parallel agents, full integration `xcodebuild` clean + `xcodebuild test` green.

**New iOS features (parity with macOS)**
- [Voice] **Voice assistant lifecycle on iOS** — was modal-only; now full coordinator-driven session. New `Services/Voice/`: `VoiceSessionCoordinator.swift` (391L, state machine: idle/connecting/listening/speaking/toolRunning/error, owns lifecycle + transcript persistence via `ai.saveConversation`), `VoiceSystemPromptClient.swift` (server-fetched persona with 60s TTL cache + offline fallback — replaces locally-built stale prompt), `VoiceToolRegistry.swift` (Gemini function declarations + `VoiceToolExecutor` protocol + iOS adapter calling `AIChatService.processVoiceToolCall`), `VoiceAudioCapture.swift` (AVAudioEngine 16kHz PCM16 capture). `VoiceIntent.swift` — `StartVoiceAssistantIntent` AppIntent + `TodusVoiceAppShortcuts` provider so Siri Shortcut serves as the iOS-equivalent of macOS's global hotkey. `Features/Settings/VoiceAssistantSettingsView.swift` mirrors macOS `voiceAssistantSection` (enable toggle, auto-stop idle toggle, Siri Shortcut hint with Shortcuts.app deep-link, reset persona cache, live status row). Wired into `AppServices` + `TodosApp` (`.task` subscribes to `.todusStartVoiceSession` notification, hydrates SwiftData main context, calls `coordinator.start()`).
- [Docs] **Native iOS Docs shell** — was web shim only. New `Domain/DocTypes.swift` (DTOs mirroring macOS), `Services/Docs/DocsService.swift` (`@MainActor @Observable`, refresh/list/create/update/delete/move/star/togglePin/search, auto-creates Personal workspace), `Features/Docs/DocsListView.swift` (NavigationSplitView on iPad, NavigationStack on iPhone, recursive nested doc rows, pull-to-refresh, context menu, swipe actions, empty state, ~290L), `Features/Docs/DocEditorView.swift` (thin native nav wrapper around existing `DocsWebView` — preserves web fallback). `DocsWebView` gained optional `docId` param for deep linking; legacy callers unchanged. `MoreSheetView` exposes native Docs + "Docs (Web)" fallback (no removal of legacy).
- [Settings] **Email automation policy controls on iOS** — `Features/Settings/EmailAutomationPolicyView.swift` (excluded-sender add/list/swipe-to-delete, auto-send experiment toggle with confirmation, workday start/end hour pickers, reset to recommended). NavigationLink added in `SettingsView.swift::emailSection`. Persists via AppServices, pushes on disappear.
- [Tasks] **Compound intent parser refinements on iOS** — `Services/Parsing/CompoundIntentParser.swift` patched with word-boundary regex (port of macOS refinements) — handles Swedish "och" + English "and" connectors with proper `\b` boundary checks. `RemoteFirstTaskParsingService` exposes `parseCompoundLocally(...)` hook so callers can get multi-intent results.
- [Onboarding] **Branded startup card on iOS** — `App/StartupOnboardingView.swift` (~150L). Hero squircle logo, "Get started" + "I already have an account". Wired into `RootView` ahead of AuthView. Existing installs auto-skip via migration check (any prior onboarding flag set or authenticated session). Matches macOS `MacStartupOnboardingView` brand presence.

**Tests — stood up real coverage**
- Before: 2 files, 9 tests, ~5% coverage. After: 10 files, **66 tests pass, 0 fail, 15 skipped** (skipped tests document required DI seams).
- New: `AuthServiceTests` (12 tests — C1 deep-link rejection, preloadTokens determinism, init→auth transition, token preview safety), `TodosAPIClientTests` (8 tests — superjson Date-meta envelope, omitted-meta plain payload, nested-date dotted path, batch wrap with String/Int H16 regression pin), `AIChatServiceTests` (12 tests — CRLF / LF classify, `[DONE]` with/without trailing CR H14 pin, heartbeat skip, chunk-boundary residual, replay end-to-end, malformed-JSON tolerance), `EmailServiceTests`, `AppleRemindersSyncServiceTests`, `NetworkMonitorTests`, `AppThemeAvatarCacheTests`, `RemoteFirstTaskParsingServiceTests`.
- Minimal non-breaking seams added: `TodosAPIClient.swift` exposes `superjsonWrap_forTesting` via `TodosAPIClientTestSeam`; `AIChatService.swift` extracts `SSELineParser` enum (production loop unchanged — pure helper).
- `TodosUITests` target stood up via xcodegen. Smoke test (`app.launch()` + window-exists). Manual follow-up: implement `--ui-testing` launch-arg stub in `AppServices` for deeper E2E.

**Infrastructure**
- [Build] **Duplicate `LocalModelStateStore.swift` resolved** — `App/LocalModelStateStore.swift` (51L stub placeholder) collided with `Services/AI/Local/LocalModelStateStore.swift` (188L real impl used by `ModelDownloadService` + `MLXInferenceService`). Renamed stub to `LocalModelStateStore_DEPRECATED.swift`, emptied class definition. Was blocking all builds. Safe to delete from disk in next cleanup.

**Verification**
- `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -sdk iphonesimulator build` → **BUILD SUCCEEDED**
- `xcodebuild ... -only-testing:TodusTests test` → **TEST SUCCEEDED** (66 / 0 / 15, 0.30s)

**Manual follow-ups**
1. Open in Xcode + run on simulator/device (sandbox blocks CoreSimulator).
2. Activate Siri Shortcut "Start Voice Assistant" via Shortcuts app to enable voice.
3. Conversation history migrates Keychain → file system on first launch (transparent).
4. AppTheme avatar cache migrates UserDefaults → file system on first launch (transparent).
5. Implement `--ui-testing` AppServices stub when ready for deeper E2E UI tests.
6. Apple `com.apple.developer.mail-client` entitlement still pending (existing TODO).

Full detail: `TASK.md` "Current iOS Parity + Hardening Sprint" + per-bug entries in `CODE_REVIEW_BACKLOG.md` "2026-05-17 — iOS Bug-Hunt + UX-Polish Audit".

## [2026-05-17] macOS regression sweep (post-parity)

Final regression hunt over the parity-wave diff. 10 high-confidence findings, 6 parallel fixers, **BUILD SUCCEEDED** after each. Headlines:

- **Compose duplicate send with attachments** ([`MacEmailComposeView.swift`](apps/macos/TodusMac/Views/Email/MacEmailComposeView.swift)) — every email with an attachment was being POSTed to `mail.send` twice (once via `emailService.sendEmail`, again via `MacDraftService.send`). Now routes attachment sends exclusively through `MacDraftService.send` so each message ships once.
- **Voice transcripts overwritten by final delta** ([`GeminiLiveProvider.swift`](apps/macos/TodusMac/Services/Voice/GeminiLiveProvider.swift), [`VoiceSessionCoordinator.swift`](apps/macos/TodusMac/Services/Voice/VoiceSessionCoordinator.swift)) — Gemini Live emits incremental transcription chunks; the provider was tagging every chunk `isFinal: true`, so the coordinator's `userTranscript = text` replace path discarded all but the last fragment. Flipped to `isFinal: false` so the existing `+=` accumulator captures the full turn before `turnComplete`.
- **Calendar picker dead** ([`MacEventEditSheet.swift`](apps/macos/TodusMac/Views/Calendar/MacEventEditSheet.swift), [`CalendarService.swift`](apps/macos/TodusMac/Services/Calendar/CalendarService.swift)) — sheet bound `selectedCalendarSourceId` but `createEvent`/`updateEvent` ignored it and hardcoded `defaultCalendarForNewEvents`. Plumbed `calendarIdentifier:` through both; picker now persists.
- **Reminders sync oscillation** ([`AppleRemindersSyncService.swift`](apps/macos/TodusMac/Services/Reminders/AppleRemindersSyncService.swift)) — `upsert` unconditionally set `.pendingUpload` after every EKReminder save, including just-imported tasks, causing per-pass redundant upserts. Preserved `.synced` when the only change was attaching a freshly imported `reminderIdentifier`.
- **Reminders delete silent on EventKit errors** — `try?` swallowed failures; switched to `do/catch` with `AppLogger.shared.log` so deletions don't ghost.
- **`GoogleCalendarService.refresh` nuked newer in-flight task** — unconditional `inflightRefresh = nil` post-await; now guarded with identity check `if inflightRefresh == task`.
- **`MacAIChatService.send_email` dropped `connectionId`** — multi-account users always sent from the server-side default. Threaded `connectionId` through `MacSendEmailArgs` → `EmailDraft.fromConnectionId` → `SendEmailInput`.
- **`VoiceSessionCoordinator.attachAudioInput` captured stale continuation** — push-to-talk re-press cycled the continuation but the broker closure still held the old one. Now reads `self.audioSendContinuation` inside the MainActor hop so each yield uses the current stream.
- **Compose autosave phantom Cc/Bcc** ([`MacEmailComposeView.swift`](apps/macos/TodusMac/Views/Email/MacEmailComposeView.swift)) — explicit `clearedCc` / `clearedBcc` flags persisted alongside autosave so removed recipients don't resurrect on next open.
- **Gmail connect poll too short** ([`EmailService.swift`](apps/macos/TodusMac/Services/Email/EmailService.swift)) — extended 6×500ms → 12×750ms (9s budget) and softened the timeout message to "Still connecting — refresh in a moment to confirm." so slow backends don't report a false "Could not link your Gmail account".

Build: `xcodebuild -project apps/macos/TodusMac.xcodeproj -scheme TodusMac -destination 'platform=macOS' build` → **BUILD SUCCEEDED**.

## [2026-05-17] macOS app hardening + iOS feature parity sweep

Multi-pass audit + remediation of `apps/macos/TodusMac`: critical/high bug fixes across mail, tasks, calendar, AI, voice, and auth; ~45 UX polish items; and a deliberate iOS → macOS parity push that closed the largest remaining gaps in Email, Calendar, Notifications, Tasks, and Search. Full integration `xcodebuild -project apps/macos/TodusMac.xcodeproj -scheme TodusMac -destination 'platform=macOS' build` → **BUILD SUCCEEDED** with zero errors.

**Critical / high bug fixes**
- [Meetings] **C1 duplicate top-level types** — resolved via existing `project.yml` exclusions; merged the secondary toolbar action into the canonical [`MacMeetingDetailView`](apps/macos/TodusMac/Views/Meetings/MacMeetingDetailView.swift) so only one symbol survives.
- [Docs] **C2 autosave reliability** ([`MacDocEditorPane`](apps/macos/TodusMac/Views/Docs/MacDocEditorPane.swift), [`MacDocsService.swift`](apps/macos/TodusMac/Services/Docs/MacDocsService.swift)) — flush on `onDisappear` + `onChange(docId)` + debounced title autosave + 3-state save indicator (saving / saved / failed-with-retry). Replaced the placeholder "Info coming soon" popover with a real word/char count + last-updated + copyable doc id view.
- [Auth] **C3 OAuth callback validation** ([`TodusMacApp.swift`](apps/macos/TodusMac/App/TodusMacApp.swift), [`MacAppServices.swift`](apps/macos/TodusMac/App/MacAppServices.swift)) — strict host check on `todus://` callbacks; queue inbound URLs until `ModelContainer` is ready so cold-launch deep links no longer drop into the void.
- [Voice] **C4 push-to-talk hotkey release** ([`HotkeyService.swift`](apps/macos/TodusMac/Services/Voice/HotkeyService.swift), [`VoiceSessionCoordinator.swift`](apps/macos/TodusMac/Services/Voice/VoiceSessionCoordinator.swift)) — tear down the `AudioInputBroker` on key-up and emit `sendActivityEnd()` end-turn frame so Gemini Live actually closes the turn instead of stalling.
- [Voice] **C5 dual `AVAudioEngine` crash** ([`MacVoiceChatPanel.swift`](apps/macos/TodusMac/Views/Voice/MacVoiceChatPanel.swift)) — replaced `.onAppear` with `.task` + awaited sequencing so the panel never starts a second engine while the global hotkey loop is still spinning down.
- [Tasks] **C6 Apple Reminders dedup + SwiftData `@MainActor` isolation** ([`AppleRemindersSyncService.swift`](apps/macos/TodusMac/Services/Tasks/AppleRemindersSyncService.swift)) — id-keyed dedupe + main-actor isolation on SwiftData mutations.
- [Tasks] **C7 delete sync** ([`MacTasksView.swift`](apps/macos/TodusMac/Views/Tasks/MacTasksView.swift)) — routed delete through `MacTaskSyncService` with a confirmation dialog so swipe-delete no longer drifts from the server.
- [Email] Bcc / `threadId` / `connectionId` / `draftId` now plumbed through send; idempotent flush with a 5-minute orphan window; pagination cursor race fixed; spinner guard against stale-page drops; sender match by header.
- [Tasks] 4xx vs 5xx retry policy with bounded max retries; word-boundary regex for compound intent parsing; [`FolderSyncService`](apps/macos/TodusMac/Services/Tasks/FolderSyncService.swift) enforces `syncedIds`; DST gap fix in recurrence math.
- [Calendar] Refresh-storm dedup; per-calendar `sourceId`; multi-day event overlap filter; scope-missing banner + reconnect CTA; Toggle race fix; `accessRole` plumbed end-to-end.
- [AI/Voice] `cancelStream` race closed via generation counter; tool exec cancellation gates; disconnect reentrancy guard; mic teardown on `.error`; serialized audio send queue with backpressure; `functionCall.id` fallback; `AudioPlayer._isPlaying` derived from buffer count; polling cross-group leak closed.
- [Auth] Restore-flash gone; profile fetch gated on session; folder `createdAt` drop fixed; settings now persists the full shape; voice context guard; OTP digit filter.

**iOS → macOS parity features (new)**
- [Email compose] **Attachments + signatures + live validation + rich text shortcuts** ([`MacEmailComposeView.swift`](apps/macos/TodusMac/Views/Email/MacEmailComposeView.swift), [`MacDraftService.swift`](apps/macos/TodusMac/Services/Email/MacDraftService.swift), [new] [`MacSignatureStore.swift`](apps/macos/TodusMac/Services/Email/MacSignatureStore.swift), [`MacSettingsView.swift`](apps/macos/TodusMac/Views/Settings/MacSettingsView.swift)) — `NSOpenPanel` attachment chips, base64 send through `MacDraftService.SendInput.attachments`; per-connection signatures stored in `MacSignatureStore` with a Settings card; live recipient validation; underline button + ⌘B / ⌘I / ⌘U shortcuts.
- [Email thread] **Verification code + tracking info chips, smart-action toolbar, snooze reminders** ([`MacEmailThreadView.swift`](apps/macos/TodusMac/Views/Email/MacEmailThreadView.swift), [`MacNotificationService.swift`](apps/macos/TodusMac/Services/Notifications/MacNotificationService.swift)) — regex-based verification-code chip with one-shot auto-copy; UPS / FedEx / USPS / order-number tracking chip; toolbar with Create Task / Create Event / Generate Reply (inline spinners); "Remind me about this…" with preset snooze + custom date picker → `scheduleEmailReminder`.
- [Calendar] **Native in-app event editor** ([new] [`MacEventEditSheet.swift`](apps/macos/TodusMac/Views/Calendar/MacEventEditSheet.swift)) — create / edit / delete inside the app (replaces Calendar.app delegation); "Open in Calendar.app" demoted to a context-menu fallback.
- [Notifications] **Full category + action registration** ([`MacNotificationService.swift`](apps/macos/TodusMac/Services/Notifications/MacNotificationService.swift), [`MacAppDelegate.swift`](apps/macos/TodusMac/App/MacAppDelegate.swift)) — `TASK_REMINDER`, `EMAIL`, `EMAIL_REMINDER`, `DUE_TASKS`, `AI_RESPONSE` categories with `TASK_COMPLETE`, `TASK_SNOOZE`, `ARCHIVE_EMAIL` actions; `UNUserNotificationCenterDelegate` implements `willPresent` (foreground banner) + `didReceive` routing for every type.
- [Tasks] **Recurrence + checklist + attachments** ([`MacTasksView.swift`](apps/macos/TodusMac/Views/Tasks/MacTasksView.swift), `TaskRecord` model) — RRULE-compatible None / Daily / Weekly / Monthly / Yearly; per-item checklist with live persistence; `NSOpenPanel` attachments copied to `Application Support/TaskAttachments/{taskId}/` with relative-path storage; JSON-backed accessors on `TaskRecord`.
- [Search] **Cross-entity search** ([`MacSearchView.swift`](apps/macos/TodusMac/Views/Search/MacSearchView.swift)) — tasks + emails + events + people with category chips (All / Tasks / Emails / Events / People), recent searches persisted via `@AppStorage` with a clear button, debounced 60-day calendar search, keyboard nav (↑ / ↓ / ⌘1–5 / ⌘↩), people derived from email senders.
- [Sharing] **Inbound `todus://share?slug=...` deep links** ([`TodusMacApp.swift`](apps/macos/TodusMac/App/TodusMacApp.swift), [`MacRootView.swift`](apps/macos/TodusMac/Views/MacRootView.swift), [new] [`MacSharedConversationView.swift`](apps/macos/TodusMac/Views/Sharing/MacSharedConversationView.swift)) — `handleIncomingURL` posts a `NotificationCenter` event; `MacRootView` presents the read-only sheet with password unlock + "Save to my conversations" via `shareService.importShare`.
- [Sidebar] **Restored Meetings entry** ([`MacSidebarView.swift`](apps/macos/TodusMac/Views/MacSidebarView.swift)).

**UX polish (~45 items)**
- Destructive confirmations (Log Out, task delete, folder delete) across Settings + Tasks.
- Toasts for: send failure, event creation, restore task, `openInCalendarApp` failure, `moveEvent` completion.
- Accessibility labels on icon-only buttons across Voice / Assistant / Calendar / Local Models.
- Notification routing via `onOpen` closure: `taskDue → tasks`, `importantEmail → thread`, `event → calendar`.
- Home briefing tap → thread deep link.
- Search clear (×), Meetings search clear, Local Models button-wrapped rows.
- 3-state save indicator, docs loading skeleton, grid / list segmented picker, outline row hover.
- Onboarding skip de-emphasized; Q&A button color reflects state; transcript "Show all (count)".
- Calendar all-day **Copy Date**; multi-day events now render in every spanned column.
- Empty search → **Create task '<query>'**.

**Files**
- New: [`MacSignatureStore.swift`](apps/macos/TodusMac/Services/Email/MacSignatureStore.swift), [`MacEventEditSheet.swift`](apps/macos/TodusMac/Views/Calendar/MacEventEditSheet.swift), [`MacSharedConversationView.swift`](apps/macos/TodusMac/Views/Sharing/MacSharedConversationView.swift) (plus `VoiceSessionCoordinator.swift` already untracked).
- Modified: ~35 files across `apps/macos/TodusMac/{App,Services,Views}/**` — see `git status` for the full list.

**Verification**
- `xcodebuild -project apps/macos/TodusMac.xcodeproj -scheme TodusMac -destination 'platform=macOS' build` → **BUILD SUCCEEDED** (zero errors, zero warnings introduced by this sweep).

**Manual follow-ups (out of scope this session)**
1. macOS Widget extension is wired in `project.yml`; needs a real-data verification pass through `MacWidgetUpdateManager`.
2. `WakeWordService` still a stub — Picovoice Porcupine integration deferred to Phase 1.5.
3. `GroupChatService` polling not yet migrated to the WebSocket Durable Object subscription (TODO in code).
4. `MacContentHeaderView` accessibility labels landed but top buttons still TODO real actions.
5. No XCTest target exists for macOS (only iOS has `TodusTests`). Stand up `TodusMacTests` as a follow-up.

Cross-reference: parity matrix added in [`PARITY_CHECKLIST.md`](PARITY_CHECKLIST.md) section **7) iOS ↔ macOS Feature Parity Matrix**.

## [2026-05-17] Bug-hunt + UX-polish: iOS app sweep (6 surfaces)

Multi-agent audit + remediation across iOS surfaces. 5 critical + 17 high + 46 medium bugs + 84 polish items addressed. Full integration `xcodebuild` clean.

**Critical/security**
- [Auth] **Deep-link token-injection blocked** ([`packages/swift-auth/Sources/TodusAuth/AuthService.swift`](packages/swift-auth/Sources/TodusAuth/AuthService.swift)) — `handleAuthCallback` strictly requires unexpired `pendingAuthFlowExpiresAt` regardless of `isAuthenticated`. Apple Sign In also sets the window (was Google-only) + adds nonce. Sentinel consumed on accept → single-use deep links.
- [Auth] **Stale refresh-token leak across re-login** (`AuthService.completeAuthentication`) — JWT-only branch clears `refreshToken`/`currentSessionId`; first two branches clear `currentSessionId` when callback omits one. Prevents cross-account session bleed.
- [Auth] **Sign-out hardened** — best-effort server revoke + synchronous Keychain delete on `signOut()` so suspend mid-logout can't resurrect tokens.
- [Notifications] **Notification taps revived** ([`apps/ios/Todus/Todus/App/TodosApp.swift`](apps/ios/Todus/Todus/App/TodosApp.swift)) — default-action branch routes email-thread, AI-conversation, due-task, email-reminder taps. Was dead — only `TASK_COMPLETE`/`TASK_SNOOZE` worked.
- [AI] **Mutation confirmation deadlock fixed** ([`Features/AI/AIChatView.swift`](apps/ios/Todus/Todus/Features/AI/AIChatView.swift), [`Services/AI/AIChatService.swift`](apps/ios/Todus/Todus/Services/AI/AIChatService.swift)) — `.confirmationDialog` bound to `pendingMutationConfirmation`. `send_email`/`update_calendar_event`/`delete_calendar_event` hung forever. `cancelStream` drains mutation continuations + resets `streamFailed`.
- [Calendar] **Permission view stuck loading after grant** ([`Features/Calendar/CalendarPermissionView.swift`](apps/ios/Todus/Todus/Features/Calendar/CalendarPermissionView.swift)) — `.onReceive(.todusCalendarAuthorizationDidChange)` + scenePhase re-read.

**High-impact**
- [Email] `EmailService` actions (`toggleStar`, `markAsSpam`, `markAsRead`, `markAsUnread`, `archiveThreads`) return `Bool`; star toggle rolls back on failure; pagination dedupe replaces in-place when newer.
- [Tasks] Capture rollback no longer races concurrent enrichment; `RemoteFirstTaskParsingService` preserves `lowConfidence`; Reminders sync bounded recursion (3 retries) + removed no-op guard.
- [Calendar] Day view fetches unified events (was Apple-only); Google event tap no-op fixed (provider-prefix strip + retry-then-alert); `EKWrapper` deleted-calendar force-unwrap removed.
- [AI] SSE parser trims `\r\n`; `flushTokenBuffer` bails on stale messageID; calendar snapshot invalidates on permission toggle; conversation persistence migrated Keychain → file system with `.completeFileProtection`.
- [Infra] TRPC body wrapped with minimal superjson (ISO-8601 Date meta); `JSONSerialization` uses `.fragmentsAllowed`; AVAudioEngine double-attach guarded; `NetworkMonitor` seeds from `currentPath`; `SubscriptionService.cancel` re-entrancy guard; `NotificationDigestService` routes via `TodosAPIClient`; `CreateSheet` validates `endDate > startDate`; AppTheme avatar cache → SHA-256 file storage; `AppPrimaryButtonStyle` uses `Color.accentColor`.

**UX polish (selected)**
- Email: archive swipe not red, send/refresh haptics, "Sending…" inline label, search-feedback distinguishes loading vs done, From row hidden on single account, recent-message relative timestamps.
- Tasks: complete/snooze haptics, context-menu delete confirmation, board column quick-add, 44pt tap targets, leading checkbox column in table view, "All clear" chip hides on truly empty, "Recent"/"Oldest" sort labels.
- Calendar: 44pt event tap targets, list empty-state CTA, scope-banner haptic+a11y, loading skeleton, long-press haptic, grid-tap creates event.
- AI: shimmer placeholder while streaming empty, always-rendered Send button, status pills in empty state (model + connected services), shuffle suggestions, contextual thinking copy from `searchState`, Share/Speak menu items, user bubble iPad maxWidth, `.updatesFrequently` VoiceOver trait.
- Infra: offline banner red tint + Retry CTA, cold-launch home skeleton, transient "Signing out…"/"Disconnect Gmail" HUDs replace blocking alerts, `@ScaledMetric` FAB, `InlineRefreshBadge` accepts `entity` for VoiceOver.
- Auth: stage-1 disabled during OTP loading, error banner auto-dismiss after 6s, OTP verify/resend spinner overlay (visible above keyboard), red email-validation hint, `canOpenURL` guard on mailto, accessibilityHints on social buttons, bell-icon accessibilityHidden.

**Verification**
- `swift build` (packages/swift-auth): Build complete.
- `xcodebuild -scheme Todus -sdk iphonesimulator build`: **BUILD SUCCEEDED** (full integration across all 6 surfaces).

**Manual follow-ups**
1. Open in Xcode and run on simulator/device — sandbox can't launch CoreSimulator for live UI smoke test.
2. AI conversation history migrates Keychain → `Application Support/ai-conversations.json` on first launch.
3. AppTheme avatar cache migrates UserDefaults blobs → file cache on first `loadFromCache`.
4. C1 single-use deep links non-replayable; confirm no legitimate flow needs replay (none expected).

Full per-bug detail in [`CODE_REVIEW_BACKLOG.md`](CODE_REVIEW_BACKLOG.md) under "2026-05-17 — iOS Bug-Hunt + UX-Polish Audit".

## [2026-05-10] Feature — Phase 1 voice assistant (macOS): global hotkey, status state machine, voice tools, Mem0 ingest

- [Feature] **Backend `GET /api/ai/voice/system-prompt`** ([`apps/server/src/routes/ai.ts`](apps/server/src/routes/ai.ts)) — Bearer-auth route returns one composed system instruction (Todus voice persona + AI profile + Mem0 memories) ready to drop into Gemini Live's `setup.systemInstruction`. Reuses `getCachedMemories`, `formatMemoriesForPrompt`, `getSharedAIProfilePromptForUser` so voice and text chat share context. Failures fall back to a default persona — voice never breaks if Mem0 is down.
- [Feature] **`ai.saveConversation` ingests voice transcripts into Mem0** ([`apps/server/src/trpc/routes/ai/conversations.ts`](apps/server/src/trpc/routes/ai/conversations.ts)). Previously only `/api/ai/chat` wrote to Mem0; voice never went through that route, so "remember X" said over voice was lost. Now the most-recent user/assistant pair is fire-and-forget posted to Mem0 on every save, cache invalidated + preloaded so the next session sees the memory immediately.
- [Feature] **macOS voice services (`apps/macos/TodusMac/Services/Voice/`)**:
  - `VoiceSystemPromptClient.swift` — fetches the system prompt with 60s cache + offline fallback persona.
  - `VoiceToolRegistry.swift` — Gemini function declarations (`create_task`, `update_task`, `delete_task`, `get_time`) + `VoiceToolExecutor` protocol (Pi-portable seam).
  - `MacAIChatService.executeVoiceTool` — runs the same SwiftData mutations the text-chat tools use, returns Gemini-shaped JSON.
  - `AudioInputBroker.swift` — single-tap AVAudioEngine fan-out so wake-word + Live can share frames without crashing the engine.
  - `HotkeyService.swift` — global ⌘⇧Space push-to-talk via Carbon `RegisterEventHotKey` (works inside App Sandbox without Input Monitoring permission).
  - `WakeWordService.swift` — Phase 1 stub fail-softing as `[Wake] disabled — hotkey only`. Phase 1.5 plugs in Picovoice Porcupine with the built-in `"computer"` keyword.
  - `VoiceSessionCoordinator.swift` — `@Observable` state machine (`idle`, `wakeListening`, `triggered`, `recording`, `thinking`, `speaking`, `toolRunning`, `interrupted`, `error`, `sleeping`) with logged transitions, transcript persistence via `ai.saveConversation`, and tool dispatch.
  - `VoiceStatusWindow.swift` — floating status panel with state pill + live transcript + last tool call.
- [Feature] **Settings → Voice Assistant** ([`MacSettingsView.swift`](apps/macos/TodusMac/Views/Settings/MacSettingsView.swift)) — master toggle ("Press ⌘⇧Space to talk to Todus") and always-listening toggle. Both default OFF — the always-on mic is opt-in.
- [Feature] **`MacAppServices.applyVoiceAssistantState`** drives the coordinator from saved prefs so toggling Settings registers/unregisters the hotkey live. The chat panel temporarily yields the mic and re-arms the global loop on close.
- [Files] `apps/server/src/routes/ai.ts`, `apps/server/src/trpc/routes/ai/conversations.ts`, `apps/macos/TodusMac/Services/Voice/VoiceSystemPromptClient.swift`, `apps/macos/TodusMac/Services/Voice/VoiceToolRegistry.swift`, `apps/macos/TodusMac/Services/Voice/AudioInputBroker.swift`, `apps/macos/TodusMac/Services/Voice/HotkeyService.swift`, `apps/macos/TodusMac/Services/Voice/WakeWordService.swift`, `apps/macos/TodusMac/Services/Voice/VoiceSessionCoordinator.swift`, `apps/macos/TodusMac/Views/Voice/VoiceStatusWindow.swift`, `apps/macos/TodusMac/Services/AI/MacAIChatService.swift`, `apps/macos/TodusMac/App/MacAppServices.swift`, `apps/macos/TodusMac/App/TodusMacApp.swift`, `apps/macos/TodusMac/Views/Voice/MacVoiceChatPanel.swift`, `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`, `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`, `docs/voice/PHASE_1.md`, `CHANGELOG.md`, `TASK.md`

## [2026-04-29] Fix — review follow-up for shard paging and compound parsing regressions

- [Fix] **Shard-backed mail pagination now uses an opaque composite cursor instead of a timestamp-only cutoff.** `apps/server/src/routes/agent/db/index.ts`, `apps/server/src/routes/agent/index.ts`, and `apps/server/src/lib/server-utils.ts` now order paged thread queries by `(latestReceivedOn DESC, id DESC)`, encode page tokens as `{ latestReceivedOn, id }`, and propagate the DB helper's real `nextPageToken` through shard aggregation. This prevents same-timestamp rows from being skipped at shard page boundaries and keeps single-shard exact-page-size pagination working.
- [Fix] **Web NLP quick-add no longer turns trailing numbers into times unless a date marker exists.** `apps/web/lib/nlp/parse-natural-language.ts` now gates the bare tail-number pattern behind a detected relative/weekday date, so inputs like `Buy milk 2` keep the `2` in the task title instead of silently creating a due date.
- [Fix] **Web compound parsing now matches native cleanup/reference handling for Swedish follow-up words.** The same parser now recognizes ASCII spellings like `i forvag` / `efterat`, treats `sen` / `sedan` as true after-references instead of leaving them in the captured title, and strips those markers back out after resolving the relative date.
- [Fix] **Native compound-intent parsing only splits on conjunctions when the right-hand clause actually starts like a new action.** Both `apps/ios/Todus/Todus/Services/Parsing/CompoundIntentParser.swift` and `apps/macos/TodusMac/Services/Tasks/CompoundIntentParser.swift` now require a likely verb-led clause after `and` / `och`, preventing ordinary titles like `Lunch with Sarah and Tom tomorrow` from being broken into multiple captures. The macOS classifier now also checks email intents before event keywords using word-boundary matching, so phrases like `maila honom presentationen innan` stay email intents instead of incorrectly opening calendar creation.
- [Verification] **Native parser regression coverage expanded.** `apps/ios/Todus/TodusTests/LocalTaskParsingServiceTests.swift` now covers the ordinary-title no-split case and confirms verb-led follow-up clauses still split into separate intents.

## [2026-04-27] Feature — Location field added to user settings, piped into AI profile

- [Feature] **`userSettingsSchema`** in [`apps/server/src/lib/schemas.ts`](apps/server/src/lib/schemas.ts) gains a `location: z.string().default('')` field. Backward-compatible: JSONB storage requires no migration; old clients that don't send `location` receive the `''` default via `mergeUserSettings`.
- [Feature] **`buildAIProfilePrompt`** now includes `- Location: <value>` in the `## Locale` section when the user has set a location. The line is omitted entirely when the field is empty so the prompt stays clean for users who haven't configured it. Result: the AI automatically knows the user's city/country and can give location-aware answers (local times, geographic references, nearby services) without the user having to repeat it.
- [Feature] **Web settings** ([`apps/web/app/(routes)/settings/general/page.tsx`](<apps/web/app/(routes)/settings/general/page.tsx>)) — a "Location" text input (with `MapPin` icon, placeholder "e.g. Oslo, Norway") appears beside the Language and Timezone selects. Saved with the rest of the general-settings form.
- [Feature] **iOS** (`AIAssistantSettingsView` in [`SettingsView.swift`](apps/ios/Todus/Todus/Features/Settings/SettingsView.swift)) — a `TextField` row for Location appears before "Context about you". `AppServices.location` persists to `UserDefaults` and is synced via `loadSharedAIProfile` / `saveSharedAIProfile`. `SharedAIProfileSaveInput` gains the `location` field. `MailAssistantSettingsResponse.Settings` gains `location: String?` (optional for backward compat).
- [Feature] **macOS** (`aiAssistantSection` in [`MacSettingsView.swift`](apps/macos/TodusMac/Views/Settings/MacSettingsView.swift)) — same text field in the styled card layout, bound to `MacAppServices.location`. Identical sync/save flow to iOS.
- [Files] `apps/server/src/lib/schemas.ts`, `apps/server/src/lib/ai-profile.ts`, `apps/web/app/(routes)/settings/general/page.tsx`, `apps/ios/Todus/Todus/Domain/MailAssistantModels.swift`, `apps/ios/Todus/Todus/App/AppServices.swift`, `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`, `apps/macos/TodusMac/Domain/MailAssistantModels.swift`, `apps/macos/TodusMac/App/MacAppServices.swift`, `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`, `CHANGELOG.md`

## [2026-04-27] Feature — AI gets real user context (name, email, locale, language) + speaks the user's language

- [Feature] **`buildAIProfilePrompt`** in [`apps/server/src/lib/ai-profile.ts`](apps/server/src/lib/ai-profile.ts) was rewritten to inject four new sections into every chat system prompt: (1) **About the user** — name + email so the AI can address the user correctly and produce accurate `From:` lines in drafts; (2) **Locale** — timezone, preferred language, and the user's current local date/time computed via `Intl.DateTimeFormat` so relative references like "tomorrow" and "this evening" resolve without a clarifying question; (3) **Reply language** — explicit instruction to mirror the language of the latest user message (with tone matching) and to localize all card text shown to the user (titles, summaries, button labels, suggestion chips) while keeping stable identifiers like `action` names and IDs in English; (4) the existing user-supplied `contextAboutYou` and `customPrompt` blocks, now clearly labeled as user-provided. Falls back to identity + locale defaults if `findUserSettings` errors transiently — previously this returned an empty string and dropped name/email entirely.
- [Feature] **`getSharedAIProfilePromptForUser`** now takes an optional `{ name, email }` identity argument; both call sites in [`apps/server/src/routes/ai.ts`](apps/server/src/routes/ai.ts) (the SSE chat endpoint at line ~503 and the `generateText` follow-up at line ~1315) pass `user.name` and `user.email` from the session.
- [Privacy] The user's own name and email flow only to the LLM that's already serving that user's session — same data the assistant needs to draft outgoing mail. No third parties involved; the user consented at account creation. We deliberately do not include other users' identities in this profile block.
- [Feature] **Audit:** verified all 21 card types and 6 layout primitives (`Stack`, `Card`, `Text`, `Button`, `Badge`, `Divider`) are present and consistent across server contract → web catalog → web registry → iOS dispatch → macOS dispatch. No drift.
- [Files] `apps/server/src/lib/ai-profile.ts`, `apps/server/src/routes/ai.ts`, `CHANGELOG.md`

## [2026-04-27] Fix — Generative-UI cards never rendered because the AI never saw the catalog

- [Fix] **Root cause:** `/api/ai/chat` (the SSE endpoint that web, iOS, and macOS chats all hit) builds the system prompt from `enrichedMessages` plus memory and AI-profile injections — it never appended `GENERATIVE_UI_PROMPT`. `AiChatPrompt()`, which contains the catalog instructions, is only used by the agent and brain routes. As a result the model in chat had zero knowledge of `InlineComposeCard`, `TaskListCard`, `EmailListCard`, etc., so it kept replying in plain markdown and the user never saw a draft card when asking the AI to write an email.
- [Fix] **Server:** [`apps/server/src/routes/ai.ts`](apps/server/src/routes/ai.ts) now imports `GENERATIVE_UI_PROMPT` from [`generative-ui-contract.ts`](apps/server/src/lib/generative-ui-contract.ts) and appends it to the system message right after the AI-profile injection. If no system message exists, one is prepended. The render seam in all three clients (`ChatSpecRenderer` on web, `ChatUISpecView` on iOS / macOS) was already wired — only the AI's awareness was missing.
- [Architectural] **`apps/web` is the active web product**, not `apps/mail` (which is now read-only legacy). Both have a parallel `components/generative-ui/` directory; the catalogs are functionally identical (only diff is `previewUrl: .nullable()` vs `.optional()`). The web rendering for the user lives in [`apps/web/components/create/ai-chat.tsx:601`](apps/web/components/create/ai-chat.tsx) where `<ChatSpecRenderer>` is mounted on every assistant message.
- [Files] `apps/server/src/routes/ai.ts`, `CHANGELOG.md`

## [2026-04-27] Fix — native CodeRabbit follow-up for parsing, compose, and task UI

- [Fix] **iOS and macOS local task parsing now avoid false-positive bare-number times and Unicode range drift.** `LocalTaskParsingService` only applies `tailTimeRegex` when a date keyword was already detected, stops at the first matching relative-date marker, and computes/removes consumed ranges against the original trimmed string so case-folding edge cases do not corrupt title cleanup.
- [Fix] **Compound intent parsing now respects the caller timezone and resolves Swedish relative-reference words consistently.** Both native `CompoundIntentParser` implementations use a timezone-configured `Calendar` for anchor offsets, remove the `i förväg` overlap from `containsSoonReference`, and strip the same before/after tokens they detect from final titles.
- [Fix] **Native compose/task UX regressions are closed.** iOS compound email creation now forwards the computed attachments into the compose seed, macOS reply and reply-all autosave keys no longer collide, macOS send validation now checks `to`/`cc`/`bcc`, and completed-task restore saves outside the animation block.
- [Verification] **Native app builds passed locally, and parser coverage was expanded.** `xcodebuild build` succeeded for both `apps/ios/Todus/Todus.xcodeproj` and `apps/macos/TodusMac.xcodeproj`; the new parser tests were added for the bare-tail-number regression, first relative-marker precedence, and `i förväg` compound parsing semantics, but the `TodusTests` target is currently blocked by an existing missing-`Info.plist` test-target configuration on this branch.
- [Files] `apps/ios/Todus/Todus/Features/Home/HomeView.swift`, `apps/ios/Todus/Todus/Navigation/CreateSheet.swift`, `apps/ios/Todus/Todus/Services/Parsing/{CompoundIntentParser.swift,LocalTaskParsingService.swift}`, `apps/ios/Todus/TodusTests/LocalTaskParsingServiceTests.swift`, `apps/macos/TodusMac/Services/Tasks/{CompoundIntentParser.swift,LocalTaskParsingService.swift}`, `apps/macos/TodusMac/Views/Email/MacEmailComposeView.swift`, `apps/macos/TodusMac/Views/Tasks/MacTasksView.swift`, `CHANGELOG.md`, `TASK.md`

## [2026-04-26] Feature — Offline-first support across iOS, macOS, and web

- [Feature] **Tasks, folders, and email drafts are now writable while offline on iOS.** Creating/editing tasks enqueues to `SupabaseSyncService` (already existed); folder mutations queue through new `FolderSyncService`; email compose uses a new `DraftRecord` SwiftData model so drafts survive offline. All three flush automatically on reconnect via `NetworkMonitor.onReconnect`.
- [Feature] **Same offline write queue on macOS.** New `TaskSyncService` queues task creates/updates/deletes through tRPC `tasks.sync`; `FolderSyncService` mirrors the iOS pattern; `DraftRecord` + `MacDraftService.saveAndSend`/`flushPending` handles email drafts. `MacAppServices.setupNetworkSync()` wires the `onReconnect` flush for all three.
- [Feature] **Web mutations now pause instead of fail when offline.** `networkMode: 'offlineFirst'` added to TanStack Query `defaultOptions` for both queries and mutations (with `retry: 1`). The IDB persister was already providing 24-hour read cache; mutations queued offline auto-retry on reconnect within the same tab session.
- [Feature] **`NetworkMonitor` gets an `onReconnect` callback on both iOS and macOS.** `wasConnected` tracks the previous state so only false→true transitions fire the callback, preventing spurious flushes on first launch.
- [Feature] **Offline indicator on all three platforms.** iOS: `OfflineBanner` SwiftUI view slides in from the top of the task/folder list when `networkMonitor.isConnected == false`. macOS: a slim `.ultraThinMaterial` banner with a `wifi.slash` icon overlays the content area (not the sidebar). Web: `<OfflineIndicator />` component using `useNetworkStatus` hook (`navigator.onLine` + window events) renders below the navigation bar.
- [Feature] **Backend: `folders.sync` batch upsert/delete endpoint.** Mirrors the existing `tasks.sync` pattern with discriminated-union input, `onConflictDoUpdate` with `setWhere: eq(taskFolder.userId, ...)` so cross-user overwrites are impossible, and `sql\`EXCLUDED.\*\`` references in the set block.
- [Fix] **`tasks.sync` IDOR hardened.** Added missing `setWhere: eq(task.userId, ctx.sessionUser.id)` to the existing `tasks.sync` upsert so a conflicting task ID from another user cannot overwrite that user's data.
- [Fix] **Stuck "sending" drafts recover on app restart.** `flushPending` now resets any draft still in "sending" state back to "pendingSend" before retrying, covering the crash-during-send case.
- [Files] `apps/server/src/trpc/routes/tasks.ts`, `apps/ios/Todus/Todus/Services/NetworkMonitor.swift`, `apps/ios/Todus/Todus/App/AppServices.swift`, `apps/ios/Todus/Todus/Services/Tasks/FolderSyncService.swift` (NEW), `apps/ios/Todus/Todus/Data/Models/DraftRecord.swift` (NEW), `apps/ios/Todus/Todus/Services/Drafts/DraftService.swift`, `apps/macos/TodusMac/Services/NetworkMonitor.swift`, `apps/macos/TodusMac/App/MacAppServices.swift`, `apps/macos/TodusMac/Services/Tasks/TaskSyncService.swift` (NEW), `apps/macos/TodusMac/Services/Tasks/FolderSyncService.swift` (NEW), `apps/macos/TodusMac/Data/Models/DraftRecord.swift` (NEW), `apps/macos/TodusMac/App/MacRootView.swift`, `apps/web/app/hooks/use-network-status.ts` (NEW), `apps/web/app/components/offline-indicator.tsx` (NEW), `apps/web/app/(routes)/layout.tsx`, `apps/web/providers/query-provider.tsx`, `CHANGELOG.md`, `TASK.md`

## [2026-04-26] Fix — iOS CodeRabbit review follow-up

- [Fix] **The tracked per-user Xcode scheme file is removed from version control.** `apps/ios/Todus/Todus.xcodeproj/xcuserdata/.../xcschememanagement.plist` is no longer tracked, matching the existing `xcuserdata/` ignore rule and avoiding user-specific scheme churn in the repo.
- [Fix] **Folder/item duplication and stale-filter bugs are closed on iOS.** Task board/table now recompute when `restrictToInbox` changes, folder pickers filter out already-added email/event items, and `TaskCaptureService.addItemToFolder(...)` now skips duplicate folder bookmarks before incrementing cached counts.
- [Fix] **Several native reliability issues are hardened.** The compose sheet now defers attachment file deletion until send succeeds, avatar-cache writes are flushed on background, widget refreshes use a bounded completed-task fetch with DST-safe day math, AI undo/retry flows always report completion, assistant-summary retry state stays visible, and the voice session no longer leaks audio resources if the user disconnects during startup.
- [Fix] **The native voice model now uses Google’s currently documented Live API identifier.** iOS `VoiceModelCatalog` now uses `gemini-live-2.5-flash-native-audio`, which matches current Google Cloud Live API docs instead of the invalid `gemini-3.1-flash-live-preview` value.
- [Verification] **Targeted iOS simulator build passed after the fixes.** `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` completed successfully; remaining output was warnings only.
- [Files] `apps/ios/Todus/Todus.xcodeproj/project.pbxproj`, `apps/ios/Todus/project.yml`, `apps/ios/Todus/TodosApp.swift`, `apps/ios/Todus/Todus/Features/AI/AIChatMessage.swift`, `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`, `apps/ios/Todus/Todus/Features/AI/AIAttachmentSheet.swift`, `apps/ios/Todus/Todus/Features/Calendar/CalendarListView.swift`, `apps/ios/Todus/Todus/Features/Calendar/CalendarTabView.swift`, `apps/ios/Todus/Todus/Features/Email/EmailComposeView.swift`, `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift`, `apps/ios/Todus/Todus/Features/Email/SenderAvatarView.swift`, `apps/ios/Todus/Todus/Features/Folders/*`, `apps/ios/Todus/Todus/Features/Home/HomeView.swift`, `apps/ios/Todus/Todus/Features/Tasks/{BoardView.swift,TaskTableView.swift,TasksTabView.swift}`, `apps/ios/Todus/Todus/Features/Voice/VoiceChatViewModel.swift`, `apps/ios/Todus/Todus/Services/{AI/API/Drafts/Notifications/Tasks/Voice/Widgets}/*`, `CHANGELOG.md`, `apps/ios/Todus/TASK.md`

## [2026-04-26] Fix — review follow-up for Ollama/session logout/native duplicate

- [Fix] **The duplicate iOS assistant cache source is removed again.** `AssistantPersistedCache 2.swift` is no longer referenced by the Xcode project or present on disk, so the native target does not redeclare `AssistantPersistedCache`.
- [Fix] **Choosing Ollama can no longer persist an invalid empty model.** The shared web/mail `ModelSelector` now refuses the provider switch until at least one Ollama model is installed, and when a model exists it persists the first installed model immediately.
- [Fix] **"Sign out all other devices" now preserves the current session.** `sessions.revokeAll` excludes the resolved current session id, so the new security page action matches its label instead of logging out the active browser too.
- [Files] `apps/ios/Todus/Todus.xcodeproj/project.pbxproj`, `apps/ios/Todus/Todus/Services/Email/AssistantPersistedCache 2.swift`, `apps/server/src/trpc/routes/sessions.ts`, `apps/web/components/ui/model-selector.tsx`, `apps/mail/components/ui/model-selector.tsx`, `apps/web/app/(routes)/settings/security/page.tsx`, `CHANGELOG.md`, `TASK.md`

## [2026-04-26] Fix — iOS AI chat user bubble contrast

- [Fix] **The user message bubble in the native AI sheet now has clear, restrained separation in both appearances.** User bubbles no longer reuse the generic card fill that was too close to the assistant sheet background; they now use a dedicated dynamic fill tuned to a very light gray in light mode and a very dark gray in dark mode.
- [User-facing] **User turns are readable at a glance again without looking loud.** The bubble remains subtle, but it now holds the same visual role in dark mode that it already should in light mode.
- [Files] `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift`, `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`, `CHANGELOG.md`, `apps/ios/Todus/TASK.md`

## [2026-04-26] Fix — native AI chat stream bootstrap + assistant fallback hardening

- [Fix] **iOS AI chat no longer waits for the provider before the SSE stream opens.** `/api/ai/chat` now returns the SSE response immediately, emits an initial bootstrap event, and only then waits on OpenRouter/Gemini. This prevents native clients from timing out during long tool-planning/model-startup delays that previously ended as `Connection lost — tap to retry.`
- [Fix] **Provider failures now surface as chat errors instead of a silent dropped stream.** If OpenRouter/Gemini rejects or fails before streaming content, the server emits an `error` SSE event and iOS renders that as an assistant error message.
- [Fix] **Assistant briefing now degrades on shard-pool saturation.** `assistant.getBriefing` treats shard initialization / Postgres pool-slot exhaustion as a degraded-but-recoverable condition and returns the lightweight fallback briefing instead of bubbling a 500 into Home startup.
- [Fix] **Native chat streams now tolerate slower first-token latency.** iOS sets an explicit 180-second timeout for `/api/ai/chat` streaming requests, reducing false client-side `NSURLErrorDomain -1001` failures while the backend/tool chain is still working.
- [Files] `apps/server/src/routes/ai.ts`, `apps/server/src/trpc/routes/assistant.ts`, `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`, `CHANGELOG.md`, `TASK.md`

## [2026-04-26] Fix — iOS HomeView build blockers resolved

- [Fix] **iOS Home no longer fails to compile after the Home dashboard refactor.** `HomeView` now restores the missing briefing hero/feed adapters, the proactive-suggestion loading flag, and the thread-sheet route state referenced by the updated top-level layout.
- [Architectural] **Home’s refactored top section is bridged back to the existing sections instead of duplicated.** The new hero/checklist/feed composition now maps to the already-implemented setup, assistant-briefing, and proactive-nudge sections so the file builds without introducing a second Home implementation.
- [Verification] **Native iOS build passed.** `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' build` succeeded after the patch.
- [Files] `apps/ios/Todus/Todus/Features/Home/HomeView.swift`, `CHANGELOG.md`, `TASK.md`

## [2026-04-26] Fix — targeted web CodeRabbit follow-up

- [Fix] **Unified inbox infinite queries no longer create duplicate cache entries.** `useThreads()` now calls `trpcClient.mail.listThreadsMulti.query()` directly inside the outer `useInfiniteQuery` instead of nesting `queryClient.fetchQuery(...)`, so the multi-connection feed uses a single query lifecycle and cache entry.
- [Fix] **Settings navigation titles now follow the app i18n path.** The AI settings item now uses the existing `navigation.settings.ai` key, and billing uses the new `navigation.settings.billing` key instead of hardcoded strings.
- [Fix] **Attachment card press events no longer allow download param collisions.** Download-specific params are emitted under `downloadParams` so they cannot overwrite top-level event fields like `action`, `name`, or `mimeType`.
- [Fix] **Compose and AI settings polish:** compose-sheet close fallback now uses React Router state instead of `window.history.length`, and the Ollama URL success toast now only fires after the save mutation succeeds.
- [Fix] **Rendering, accessibility, and locale cleanup:** `WeeklyAgendaCard` now guards `parseISO()` output with `isValid()`, source rows suppress invalid timestamps, source favicon URLs encode `iconHint`, the full `ModelSelector` labels are programmatically tied to their Radix triggers, `CopyableTextCard` only shows copied state after successful local clipboard writes, the `open_attachment` catalog now uses nullable `previewUrl`, Hungarian danger-zone copy is translated, Hindi `cancel` labels are standardized, the French default-email copy is provider-agnostic, Czech `meetings` navigation labels are translated to `Schůzky`, and Catalan spam-delete confirmation stays in the file’s formal register.
- [Fix] **Stream handling, session i18n, and compose resilience:** Ollama pull streams now process the final buffered chunk and surface streamed `error` objects, the security sessions page now uses i18n keys instead of hardcoded English, inline draft autosave returns to `saved` after optimistic sync dispatch, draft update payloads are runtime-validated before use, AI chat markdown normalization uses a non-printable sentinel, and failed `append()` calls now restore the composer and pending attachments before showing an error toast.
- [Files] `apps/web/hooks/use-threads.ts`, `apps/web/config/navigation.ts`, `apps/web/components/ui/model-selector.tsx`, `apps/web/components/generative-ui/components/{AttachmentCard,WeeklyAgendaCard,CopyableTextCard}.tsx`, `apps/web/components/create/ai-sources.tsx`, `apps/web/components/generative-ui/catalog.ts`, `apps/web/app/(routes)/mail/{compose/search}/page.tsx`, `apps/web/app/(routes)/settings/ai/page.tsx`, `apps/web/messages/{en,cs,ca,fr,hi,hu}.json`, `CHANGELOG.md`, `TASK.md`

## [2026-04-26] Fix — billing portal cancellation path + Ollama URL sync

- [Fix] **Web + mail billing settings no longer guess the Pro SKU when canceling.** Paid users now open the hosted billing portal for cancellation and billing management, which works for both monthly and annual Pro without relying on normalized `plan === 'pro'` state.
- [Fix] **Billing plan copy now matches the current product surface.** The shared web/mail settings pages only advertise the active `free` and `pro` tiers.
- [Fix] **Saved Ollama endpoints load correctly in settings.** The AI settings URL input now resyncs from async user settings after load, so existing custom `ollamaBaseUrl` values are shown instead of the localhost fallback and are not accidentally overwritten on save.
- [Files] `apps/web/app/(routes)/settings/billing/page.tsx`, `apps/mail/app/(routes)/settings/billing/page.tsx`, `apps/web/app/(routes)/settings/ai/page.tsx`, `apps/mail/app/(routes)/settings/ai/page.tsx`, `CHANGELOG.md`

## [2026-04-26] Server — folder schema, summary query, generative UI docs

- [Schema] **`task_folder.updated_at`** now uses Drizzle `.$onUpdate(() => new Date())` so ORM-driven updates refresh the timestamp like other tables.
- [Schema] **`folder_item`** gains composite index `(folder_id, position)` for folder content ordered by position; migration `0053_needy_ben_urich.sql`.
- [Performance] **`folders.summary`** uses `COUNT(*) … GROUP BY` for per-folder task, chat, and folder-item totals and `ROW_NUMBER() … <= 3` subqueries for recent rows instead of loading all matching rows.
- [Docs] **Generative UI contract** — `SuggestionsCard` params documented to match `Button.actionParams` (string values only; JSON-stringify structured data).
- [Files] `apps/server/src/db/schema.ts`, `apps/server/src/db/migrations/0053_needy_ben_urich.sql`, `apps/server/src/trpc/routes/tasks.ts`, `apps/server/src/lib/generative-ui-contract.ts`, `CHANGELOG.md`

## [2026-04-26] Fix — native live voice chat moves to Gemini 3.1 Flash Live

- [Fix] **iOS + macOS live voice chat now use Google’s current Live API model.** The shared native voice-session defaults no longer point at deprecated `models/gemini-2.0-flash-live-001`; both apps now open sessions with `gemini-3.1-flash-live-preview`, matching Google’s current Live model docs and avoiding the rejected `bidiGenerateContent` setup seen in production.
- [Fix] **Live-session text updates now use realtime input.** Mid-call text is now sent as `realtimeInput.text` instead of `clientContent`, aligning the native providers with the current Gemini Live API contract for in-session text.
- [User-facing] **Voice UI now names the active model.** The iOS and macOS live-voice headers show `Gemini 3.1 flash live` so the surfaced model name matches the runtime model actually used for voice sessions.
- [Verification] **iOS native build passed.** `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -configuration Debug -destination 'generic/platform=iOS' build` succeeded after the patch. The macOS target remains blocked by a pre-existing unrelated compile error in `apps/macos/TodusMac/App/TodusMacApp.swift` (`FolderItemRecord` not found), so full macOS build verification could not complete from this branch state.
- [Files] `apps/ios/Todus/Todus/Services/Voice/VoiceProvider.swift`, `apps/ios/Todus/Todus/Services/Voice/GeminiLiveProvider.swift`, `apps/ios/Todus/Todus/Features/Voice/VoiceChatModalView.swift`, `apps/macos/TodusMac/Services/Voice/VoiceProvider.swift`, `apps/macos/TodusMac/Services/Voice/GeminiLiveProvider.swift`, `apps/macos/TodusMac/Views/Voice/MacVoiceChatPanel.swift`, `CHANGELOG.md`, `TASK.md`

## [2026-04-26] Fix — server billing enforcement + folder migration repair

- [Fix] **Billing cache hydration now mutates only on confirmed missing customers.** `refreshSubscriptionCache()` no longer treats every Autumn lookup failure as “customer missing”; transient provider/API failures now preserve the existing cache instead of auto-attaching `free` to whatever state Autumn already has.
- [Fix] **Zero-credit plans are enforced correctly.** `hasAiCredits()` still self-heals legacy zero-state caches, but it no longer fails open when the refreshed quota remains at zero. Only explicit unlimited plans bypass the gate.
- [Fix] **Autumn result objects are handled explicitly.** Billing, signup provisioning, and subscription flows now inspect `autumn-js` `{ data, error, statusCode }` results instead of assuming provider failures throw, which prevents silent local usage-cache drift and surfaces checkout/cancel/billing-portal failures properly.
- [Fix] **Onboarding campaign scheduling now matches Resend’s API contract.** The auth campaign sender now passes `scheduledAt` as an ISO string instead of a raw `Date`, which removes the server type error and keeps delayed onboarding sends shaped correctly for Resend.
- [Fix] **Folder migration repair now covers 0052.** `/admin/run-migrations` `mode=info` reports `mail0_task_folder` / `mail0_folder_item`, and apply mode now repairs the new folder metadata columns, `mail0_folder_item` table, unique constraint, foreign keys, and indexes alongside the earlier docs/billing fixes.
- [Fix] **Docs parent/workspace integrity.** `docs.create` and `docs.update` now validate parent ownership and workspace consistency and inherit the parent workspace when appropriate, preventing cross-user parent links and mismatched workspace trees.
- [Files] `apps/server/src/lib/billing.ts`, `apps/server/src/trpc/routes/subscription.ts`, `apps/server/src/lib/auth.ts`, `apps/server/src/trpc/routes/tasks.ts`, `apps/server/src/trpc/routes/docs.ts`, `apps/server/src/main.ts`, `CHANGELOG.md`, `TASK.md`

## [2026-04-26] Fix — shared native auth session restore hardening

- [Fix] **`packages/swift-auth` session restore now distinguishes revoked sessions from transient failures.** `AuthService`'s refresh path now returns structured outcomes instead of a flat `Bool`, so offline/network failures no longer show a false "Session expired" banner on launch, while genuinely rejected refresh tokens now clear auth state instead of booting into the authenticated shell.
- [Fix] **Confirmed-invalid sessions no longer linger as authenticated in follow-up profile checks.** `restorePersistedSession()` and `fetchUserProfile()` now sign out once `/api/auth/me` rejects both the original and refreshed token, which prevents revoked sessions from continuing to expose cached authenticated UI.
- [Fix] **Token preview redaction is consistent.** The public debug-facing `bearerTokenPreview` accessor now shows length only, matching the logging hardening and avoiding partial token disclosure in screenshots or support captures.
- [Files] `packages/swift-auth/Sources/TodusAuth/AuthService.swift`, `CHANGELOG.md`, `TASK.md`

## [2026-04-26] Feature — 6 more chat-card types + bug-audit pass on the generative-UI catalog

- [Feature] **Six new card types** added to the catalog and shipped on web, iOS, and macOS in one pass: `AttachmentCard` (file chip with mime-icon, size, open-action), `CodeBlockCard` (syntax-aware code block with language label + copy + scrolling pre), `ChecklistCard` (interactive ad-hoc checklist with optimistic local toggles, separate from real tasks), `DocumentCard` (link to a user Doc), `WeeklyAgendaCard` (compact 7-day density grid; tap navigates to a day), `MetricCard` (single-stat tile with optional delta + direction). Four new actions wired through every layer: `open_attachment`, `toggle_checklist_item`, `navigate_document`, `navigate_day`. Server prompt taught new intent mappings (`reference_attachment`, `share_code_snippet`, `generate_steps_or_checklist`, `reference_document`, `weekly_overview`, `show_single_stat`).
- [Fix] **Autosave/send race in `InlineComposeCard`** — on every platform, the debounced 600ms autosave timer is now cancelled by Send, and `isDirty` resets after each fire. Previously, an orphan autosave fired right after Send and overwrote the just-sent state.
- [Fix] **Duplicate recipients on iOS + macOS `InlineComposeCard`** — adding the same address twice (or with whitespace, or `foo@` / `@bar`) is now rejected, matching the web behavior.
- [Fix] **`groupedThreshold` clamp** — iOS + macOS list cards now `max(1, …)` the threshold so a value of `0` or `-1` from the AI no longer breaks layout (web already did this).
- [Fix] **`uiSpec` not reset on retry (macOS)** — `MacAIChatService.retryMessage` now clears `messages[idx].uiSpec` alongside content/sources/etc., so old generative-UI cards no longer bleed into the regenerated bubble. iOS already did this.
- [Fix] **macOS draft send stuck "Sending…" on failure** — promoted the macOS spec-action callback to the same 3-arg `MacChatUISpecOnAction` typealias as iOS, plumbed through every macOS card view's call sites, and wired real `(success, errorMessage)` completion in `MacAssistantPanel.handleSpecAction` for `update_draft` / `send_draft`. The InlineCompose footer now flips to "Sent" / "Failed to send" instead of hanging.
- [Polish] `CopyableTextCard` now caps height at ~280px with internal scroll on every platform — long pastes don't blow out the chat. Empty state on iOS + macOS list cards mirrors web. Web `InlineComposeCard` now displays attachment chips (name + formatted size) when the AI emits an `attachments` array. iOS now opens `previewUrl` for `open_attachment` via `UIApplication.shared.open`; macOS via `NSWorkspace.shared.open`.
- [Architectural] The catalog + contract files now describe 21 card types and 17 actions. Action params remain stringly-typed; nested payloads continue to be JSON-encoded into a single `payload` string to preserve the existing flat-string callback contract.
- [Files] `apps/server/src/lib/generative-ui-contract.ts`, `apps/mail/components/generative-ui/{catalog.ts,registry.tsx}`, `apps/mail/components/generative-ui/components/{Attachment,CodeBlock,Checklist,Document,WeeklyAgenda,Metric}Card.tsx`, `apps/mail/components/generative-ui/components/{InlineCompose,CopyableText,EmailList,SuggestionsCard}.tsx` (polish), `apps/ios/Todus/Todus/Features/AI/{ChatUISpec,CardViews,ChatUISpecView,AIChatView}.swift`, `apps/macos/TodusMac/Views/AI/ChatUISpec/{ChatUISpec,CardViews,ChatUISpecView}.swift`, `apps/macos/TodusMac/Services/AI/MacAIChatService.swift`, `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`, `CHANGELOG.md`, `TASK.md`

## [2026-04-26] Fix — AI billing unlimited-state + sidebar image-only submit

- [Fix] **Server billing:** `refreshSubscriptionCache()` now preserves Autumn `ai_usage.unlimited` in the cached subscription state instead of collapsing it to zero credits. The server stores a negative DB sentinel internally, returns `aiUsage.unlimited` to clients, and keeps `hasAiCredits()` open for unlimited plans across text chat, voice chat, and ZeroAgent chat.
- [Fix] **Web/mail AI sidebar:** image-only pasted submits now go through `append(..., { allowEmptySubmit: true })` instead of the plain `handleSubmit()` path, so attachment-only turns are no longer dropped and the pending image tray is only cleared after a successful send.
- [Fix] **Native + web billing UI:** iOS, macOS, and the mail settings billing page now render unlimited AI usage explicitly as **Unlimited** instead of showing a zero-credit exhausted state.
- [Files] `apps/server/src/lib/billing.ts`, `apps/server/src/trpc/routes/subscription.ts`, `apps/mail/components/create/ai-chat.tsx`, `apps/mail/app/(routes)/settings/billing/page.tsx`, `apps/ios/Todus/Todus/Services/Subscription/SubscriptionService.swift`, `apps/ios/Todus/Todus/Features/Settings/BillingSettingsView.swift`, `apps/macos/TodusMac/Services/Subscription/MacSubscriptionService.swift`, `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`, `CHANGELOG.md`, `TASK.md`

## [2026-04-26] Feature — Sources affordance on AI assistant messages

- [Feature] **Server:** New shared type `AISource` in [`apps/server/src/lib/ai-sources.ts`](apps/server/src/lib/ai-sources.ts) describes one piece of context the AI consumed (web result, prompt mention, injected memory, or tool-call result). [`ai.ts`](apps/server/src/routes/ai.ts) now emits a unified `context_sources` SSE event before the LLM stream, aggregating web search results, resolved `@`mentions, and Mem0 memories. The legacy `sources` event still fires so markdown `[1]` / `[2]` citations keep working.
- [Feature] **iOS:** `AIChatMessage.sources` migrated from `[WebSource]` to `[AISource]`. New [`AISourcesView.swift`](apps/ios/Todus/Todus/Features/AI/AISourcesView.swift) renders a stacked-icons "Sources" button inline with the assistant message action row (next to copy / 👍 / 👎); tapping opens a `.large`/`.medium` detents sheet listing every source with subtitle, timestamp, title, and platform icon. Web rows open inline in a follow-up sheet; thread / event / email / task rows navigate via the existing `onNavigate` map. Tool-call sources (send_email, create/update/delete_calendar_event, create/update/delete_task) are appended client-side from `AIChatService.executeSingleToolCall` so the user sees what the AI just did.
- [Feature] **iOS icons:** Added `GoogleMeetIconView`, `NotesIconView`, `DocumentIconView`, `TodusChatIconView`, `MemoryIconView`, `CompanyIconView`, and a favicon-backed `WebsiteIconView` to [`BrandIcons.swift`](apps/ios/Todus/Todus/DesignSystem/BrandIcons.swift). The Sources button + sheet share a `SourcePlatformIcon` switcher.
- [Feature] **macOS:** Mirror — new [`MacAISourcesView.swift`](apps/macos/TodusMac/Views/AI/MacAISourcesView.swift) (button + sheet + row), parallel `contextSources: [MacAISource]` field on `MacChatMessage`, and `context_sources` SSE decoding in `MacAIChatService.handleCustomEvent`. The button renders inline with the existing macOS action row.
- [Feature] **Web (component-only, not yet rendered):** New [`apps/mail/components/create/ai-sources.tsx`](apps/mail/components/create/ai-sources.tsx) exporting a `<Sources />` component (button + right-side shadcn `Sheet`) that consumes the same `AISource[]` shape. **Caveat:** the web chat goes through `useAgentChat` from `agents/ai-react`, which only surfaces AI-SDK-protocol chunks. Our raw `context_sources` SSE event bypasses that protocol so the React hook never sees it. To finish the web side, the backend needs to migrate `context_sources` onto the AI SDK `data` channel (`createDataStream` / `streamData.append`) and `ai-chat.tsx` needs to read `chatState.data` keyed to the assistant message id. The component is built and ready for that follow-up — until then native iOS + macOS render the Sources button; web does not.
- [Architectural] `AISource.id` namespacing keeps deduplication clean across event sources: web rows use `web:<url>`, mentions use `mention:<kind>:<id>`, memories use `memory:injected`, and client-built tool-call rows use `tool:<callId>`. iOS / macOS / web all dedupe by id when merging the legacy `sources` event with `context_sources`.
- [Files] `apps/server/src/lib/ai-sources.ts`, `apps/server/src/routes/ai.ts`, `apps/ios/Todus/Todus/Features/AI/AIChatMessage.swift`, `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`, `apps/ios/Todus/Todus/Features/AI/AISourcesView.swift`, `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`, `apps/ios/Todus/Todus/DesignSystem/BrandIcons.swift`, `apps/macos/TodusMac/Services/AI/MacAIChatService.swift`, `apps/macos/TodusMac/Views/AI/MacAISourcesView.swift`, `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`, `apps/mail/components/create/ai-sources.tsx`, `CHANGELOG.md`, `TASK.md`

## [2026-04-26] Fix — iOS restores floating AI FAB with native tab bar

- [Fix] **iOS:** `MainTabView` now renders the floating bottom-right AI FAB again while keeping the native tab bar and center `+` create action.
- [User-facing] The sparkles AI button is back above the tab bar instead of disappearing with the retired floating custom nav pill.
- [Files] `apps/ios/Todus/Todus/Navigation/MainTabView.swift`, `CHANGELOG.md`, `apps/ios/Todus/TASK.md`

## [2026-04-26] Feature — Generative-UI catalog gains 9 new card types across web, iOS, macOS

- [Feature] **Server contract:** [`generative-ui-contract.ts`](apps/server/src/lib/generative-ui-contract.ts) now teaches the AI nine new card types — `TaskListCard`, `EmailListCard`, `CalendarEventListCard`, `ContactListCard`, `CopyableTextCard`, `InlineComposeCard`, `SuggestionsCard`, `ActionConfirmationCard`, `QuoteCard` — plus five new actions (`update_draft`, `send_draft`, `attach_to_draft`, `copy_text`, `undo`). Intent rules updated so 2+ items of the same type render as a single list card instead of repeated individual cards.
- [Feature] **Server route:** new `drafts.update` mutation in [`drafts.ts`](apps/server/src/trpc/routes/drafts.ts) — thin alias over `createDraft`'s existing upsert path, used by the InlineComposeCard's debounced autosave.
- [Feature] **Web:** mirrored Zod schemas in [`catalog.ts`](apps/mail/components/generative-ui/catalog.ts), nine new React components in `apps/mail/components/generative-ui/components/`, and registry wiring + real `update_draft` / `send_draft` / `copy_text` / `undo` handlers in [`registry.tsx`](apps/mail/components/generative-ui/registry.tsx). The InlineComposeCard renders a fully editable + sendable email inline in chat with debounced autosave (~600ms) and recipient pills.
- [Feature] **iOS:** added 9 new props structs in [`ChatUISpec.swift`](apps/ios/Todus/Todus/Features/AI/ChatUISpec.swift), 9 new SwiftUI views in [`CardViews.swift`](apps/ios/Todus/Todus/Features/AI/CardViews.swift), and dispatch cases in [`ChatUISpecView.swift`](apps/ios/Todus/Todus/Features/AI/ChatUISpecView.swift). New `DraftService` at `apps/ios/Todus/Todus/Services/Drafts/DraftService.swift` wraps `drafts.update` + `mail.send`. Action handler in `AIChatView.handleSpecAction` reports save/send completion back to the card.
- [Feature] **macOS:** ported the entire ChatUISpec system from iOS — [`ChatUISpec.swift`](apps/macos/TodusMac/Views/AI/ChatUISpec/ChatUISpec.swift) (data model copied verbatim), [`ChatUISpecView.swift`](apps/macos/TodusMac/Views/AI/ChatUISpec/ChatUISpecView.swift) (dispatcher), [`CardViews.swift`](apps/macos/TodusMac/Views/AI/ChatUISpec/CardViews.swift) (17 SwiftUI views adapted to `MacTheme`). `MacChatMessage` gained a `uiSpec` field + `parseUISpec()`; `MacAssistantPanel.assistantBubble` now renders cards below the markdown content. New `MacDraftService` parallels the iOS one. macOS gains rich-card UI for the first time — previously markdown + tool-mutation badges only.
- [Architectural] **Spec safety:** `InlineComposeCard` on every platform locks its seed state to the initial `draftId`, so AI re-emissions for the same draft do not clobber unsent local edits. Action params stay `Record<string, string>` / `[String: String]` — nested payloads are JSON-encoded into a single `payload` string to preserve the existing callback signature.
- [Files] `apps/server/src/lib/generative-ui-contract.ts`, `apps/server/src/trpc/routes/drafts.ts`, `apps/mail/components/generative-ui/{catalog.ts,registry.tsx}`, `apps/mail/components/generative-ui/components/{TaskList,EmailList,CalendarEventList,ContactList,CopyableText,InlineCompose,Suggestions,ActionConfirmation,Quote}Card.tsx`, `apps/ios/Todus/Todus/Features/AI/{ChatUISpec.swift,ChatUISpecView.swift,CardViews.swift,AIChatView.swift}`, `apps/ios/Todus/Todus/Services/Drafts/DraftService.swift`, `apps/ios/Todus/Todus/App/AppServices.swift`, `apps/macos/TodusMac/Views/AI/ChatUISpec/{ChatUISpec.swift,ChatUISpecView.swift,CardViews.swift}`, `apps/macos/TodusMac/Services/AI/MacAIChatService.swift`, `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`, `apps/macos/TodusMac/Services/Drafts/MacDraftService.swift`, `apps/macos/TodusMac/App/MacAppServices.swift`, `CHANGELOG.md`, `TASK.md`

## [2026-04-26] Fix — iOS native tab bar restores center create action

- [Fix] **iOS:** `MainTabView` now uses the native tab order **Home / Tasks / + / Email / Calendar**. The middle `+` is action-only and immediately opens `CreateSheet`.
- [Fix] **iOS:** `Meetings` is no longer a visible native tab, but its screen remains in code and can still be presented from other flows.
- [User-facing] Home content now uses native-tab-bar spacing instead of reserving the old floating custom-bar height.
- [Files] `apps/ios/Todus/Todus/Navigation/MainTabView.swift`, `apps/ios/Todus/Todus/Features/Home/HomeView.swift`, `CHANGELOG.md`, `apps/ios/Todus/TASK.md`

## [2026-04-26] Change — Hide default-mail onboarding until Apple grants the capability

- [Fix] **iOS + macOS:** The default-mail onboarding screens are now skipped in the live onboarding flow, while the underlying views and persisted state remain in the codebase for later re-enablement.
- [User-facing] Native onboarding now ends after the notifications step instead of surfacing a broken “make Todus your mail app” step.
- [Architectural] This is a routing-only change. `DefaultMailOnboardingView`, `MacDefaultMailOnboardingView`, and `hasConfiguredDefaultMailPrompt` were intentionally preserved because `com.apple.developer.mail-client` has not yet been granted for the app IDs.
- [Files] `apps/ios/Todus/Todus/App/RootView.swift`, `apps/macos/TodusMac/App/MacRootView.swift`, `CHANGELOG.md`, `TASK.md`

## [2026-04-25] Fix — iOS uses only the native tab bar again

- [Fix] **iOS:** `MainTabView` no longer hides the native `TabView` tab bar or overlays the floating `CustomTabBar`, so the duplicate bottom navigation chrome is gone and only the standard iOS tab bar remains visible.
- [User-facing] The native tab bar now uses labeled `tabItem`s for **Home**, **Tasks**, **Email**, **Calendar**, and **Meetings**.
- [Fix] **iOS onboarding/settings:** the tab-bar customization onboarding step is skipped entirely, its progress count drops from 5 steps to 4, and the Settings entry for customizing the floating tab bar is no longer surfaced.
- [Architectural] The custom tab-bar code is intentionally kept in the codebase for later reuse, but runtime state now defaults `hasConfiguredTabBarPrompt` to complete so older installs do not get stuck on the removed step.
- [Files] `apps/ios/Todus/Todus/Navigation/MainTabView.swift`, `apps/ios/Todus/Todus/App/RootView.swift`, `apps/ios/Todus/Todus/App/AppServices.swift`, `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`, `apps/ios/Todus/status_ios.md`, `apps/ios/Todus/TASK.md`, `CHANGELOG.md`

## [2026-04-25] Fix — iOS default-mail onboarding opens the right Settings surface

- [Fix] **iOS:** `DefaultMailOnboardingView` now uses Apple’s `UIApplication.openDefaultApplicationsSettingsURLString` instead of `openSettingsURLString`, so the CTA targets the global **Default Apps** Settings page rather than Todus’s app-specific Settings page.
- [User-facing] The onboarding button label now reads **Open Default Apps**, and the helper copy explains the fallback path if iOS still lands on Todus settings on a given OS build.
- [Architectural] **iOS + macOS:** Investigation confirmed both native targets already register `mailto` in `Info.plist`, but neither entitlements file currently declares Apple’s `com.apple.developer.mail-client` capability. Without that entitlement being granted in the Apple Developer profile and provisioning setup, Todus will not appear as a selectable default mail app in system settings.
- [Files] `apps/ios/Todus/Todus/App/DefaultMailOnboardingView.swift`, `CHANGELOG.md`, `TASK.md`

## [2026-04-25] Fix — iOS AI assistant composer stays above keyboard

- [Fix] **iOS:** `MainTabView` no longer disables keyboard-safe-area handling for the entire shell. The floating custom tab bar still ignores keyboard movement, but sheets presented from the shell, including `AIChatView`, now keep their bottom insets attached to the keyboard correctly.
- [User-facing] In the AI assistant sheet, the multiline chat composer now grows upward only. The bottom controls stay above the keyboard instead of expanding underneath it.
- [Files] `apps/ios/Todus/Todus/Navigation/MainTabView.swift`, `CHANGELOG.md`

## [2026-04-25] Fix — Native navigation/settings credibility pass (iOS + macOS)

- [Fix] **iOS:** `MainTabView` now uses the existing floating `CustomTabBar` fed by `services.tabBarTabs`, while the underlying `TabView` keeps content state alive. Tab-bar onboarding and Settings customization now change the real navigation shell, including support for pinning **Meetings** into the main bar.
- [Fix] **iOS:** Thread overflow menu now has a real **Set reminder** flow with quick presets (1 hour, tonight, tomorrow morning) backed by local notifications instead of a dead-end placeholder. Reminder scheduling now reports failure when notification permission is off.
- [Fix] **iOS:** Default-mail onboarding copy/button now matches what the app can actually do on-device: it opens Todus inside Settings and explains the manual step back to **Default Apps → Email**, instead of falsely implying the CTA jumps straight there.
- [Fix] **iOS:** Email Settings toggles are now wired through the inbox. `Swipe Gestures` disables/enables mail swipe actions, and `Group by Thread` persists and drives the Threads/People inbox mode instead of being a dead preference.
- [Fix] **macOS:** Launch behavior now separates **Open on Launch** from **Resume Last Viewed Page**. `startupView` is honored by default, and last-view restore remains available as an explicit Settings toggle instead of silently overriding the launch page preference.
- [Fix] **macOS:** Existing preferences now affect real UI. `Compact Sidebar` changes sidebar column width, `Show Unread Badge` controls unread indicators/badges in Mail surfaces, and `Group by Thread` persists and drives the Threads/People inbox mode.
- [Files] `apps/ios/Todus/Todus/Navigation/MainTabView.swift`, `apps/ios/Todus/Todus/Features/Tasks/CustomTabBar.swift`, `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`, `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift`, `apps/ios/Todus/Todus/Services/Notifications/NotificationService.swift`, `apps/ios/Todus/Todus/App/DefaultMailOnboardingView.swift`, `apps/macos/TodusMac/App/MacAppServices.swift`, `apps/macos/TodusMac/App/MacRootView.swift`, `apps/macos/TodusMac/App/MacSidebarView.swift`, `apps/macos/TodusMac/Views/Email/MacEmailInboxView.swift`, `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`

## [2026-04-26] Fix — macOS app async launch compile error

- [Fix] **macOS:** `TodusMacApp.initializeApp()` now awaits `Task.yield()`, matching the current Swift concurrency requirement and fixing the Xcode build error `Expression is 'async' but is not marked with 'await'` at app launch initialization.
- [Architectural] This keeps the existing splash-screen-first startup flow intact while making the deferred `ModelContainer` initialization compile correctly on current toolchains.
- **Files:** `apps/macos/TodusMac/App/TodusMacApp.swift`, `TASK.md`

## [2026-04-25] Polish — Subscription UI fixes + voice metering (web + iOS + macOS + server)

- [Feature] **Voice chat AI usage now tracked.** `/api/ai/voice-ws` (Gemini Live proxy) gets a pre-flight credit check + per-session-minute metering on close. Estimate: 0.10 credits/minute (~$0.10/min Gemini Live blended audio rate). Idempotent close handling — both client and upstream close events route through a single `trackVoiceUsage()` flag.
- [Hardening] **Voice chat only starts billing on first billable user input.** Opening the voice sheet and idling no longer consumes credits; the proxy starts metering only after the first client audio/text/media payload. The temporary `/admin/run-migrations` repair route is no longer guarded by a committed token and now stays disabled unless `ADMIN_RUN_MIGRATIONS_TOKEN` is configured as a server secret.
- [Fix] **Legacy users no longer see "No AI credits on the free plan."** `subscription.getStatus` now self-heals: if cache shows `aiUsageLimit=0`, it synchronously calls `refreshSubscriptionCache()` which lazy-creates the Autumn customer + attaches `free`. Idempotent; one slow call, then fast forever. Existing users from before billing existed get hydrated on first settings open.
- [Fix] **Wrong upgrade URL.** iOS + macOS were opening `https://app.todus.app/pricing` (which doesn't exist) — fixed to derive the web host by stripping the `api.` subdomain prefix, with `https://todus.app/pricing` as the fallback root.
- [UX] **No more dollar amounts in the billing UI.** Per the user's call (the credit→USD conversion is internal), removed all `$N` references and "1 credit ≈ $1" footnotes from web, iOS, and macOS billing pages. Plan-includes lists now read "15 credits / month" instead of "$15 of AI usage".
- [UX] **Bigger, cleaner usage card on all three apps.** Headline is now a 5xl tabular-numerals "X / Y left" credits-remaining number, prominent percent-remaining sub, full-width thicker progress bar, used/total tabular footer. Out-of-credits banner has an inline Upgrade button (web) instead of a separate row.
- [Files] `apps/server/src/lib/billing.ts`, `apps/server/src/trpc/routes/subscription.ts`, `apps/server/src/routes/ai.ts`, `apps/mail/app/(routes)/settings/billing/page.tsx`, `apps/ios/Todus/Todus/Features/Settings/BillingSettingsView.swift`, `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`
- [Verified] Server + web `tsc --noEmit`: 0 new errors. Voice metering uses `trackCreditsUsed()` (a new generic credit-debit helper) so future per-minute or per-image AI surfaces can plug in without a token-conversion shim.

## [2026-04-25] macOS Settings — Developer mode + Auth Debug gating

- [UX] **macOS:** Settings includes a **Developer Mode** toggle (orange switch) for the same allowlisted account as iOS (`TodusDeveloperAccess`). **Auth Debug** and other debug-only rows show only when Developer Mode is on; the toggle itself is hidden for non-allowlisted users.
- [Architectural] **macOS:** `MacAppServices` persists `developerModeEnabled` under `TaskApp.developerModeEnabled` (shared key with iOS). The Xcode target now compiles `TodusDeveloperAccess.swift` and `TodusHTTPClient.swift` from `packages/swift-auth` into the app module; redundant `import TodusAuth` was removed from mac sources so the build matches the single-module `Todus` target.
- **Files:** `MacAppServices.swift`, `MacSettingsView.swift`, `MacAIChatService.swift`, `TodosAPIClient.swift`, `MacNotificationCenterView.swift`, `TodusMac.xcodeproj/project.pbxproj`

## [2026-04-25] UX — Tasks view-mode tabs match Calendar segmented control

- [UI] iOS and macOS Tasks `List` / `Board` / `Table` (and iOS `Dates`) picker now use the same **recessed track** (0.88 light / 0.13 dark) and **selected pill** (white / 0.22 dark) plus light shadow as the macOS **Calendar** `Day|Week|Month|Year` control — much clearer active state in light and dark mode.
- [Architectural] `MacTheme.segmentedTrack` / `MacTheme.segmentedSelectedPill` and `AppTheme` equivalents; Calendar’s picker reuses the macOS theme tokens.
- **Files:** `MacTheme.swift`, `AppTheme.swift`, `MacTasksView.swift`, `TasksTabView.swift`, `MacCalendarView.swift`

## [2026-04-25] Fix — Docs production schema repair

- [Ops] **Backend:** `/admin/run-migrations` now repairs the docs storage schema through the production Hyperdrive connection: creates `mail0_doc_workspace`, `mail0_doc`, docs foreign keys, indexes, and `mail0_doc.is_starred` idempotently. `mode=info` also reports docs table columns so the repair can be verified before/after running it.
- [User-facing] Once this backend is deployed and the admin repair or normal Drizzle migrations are applied, macOS/web Docs will stop returning HTTP 412 “missing doc tables”.
- **Files:** `apps/server/src/main.ts`

## [2026-04-25] Ops — GitHub Action applies Drizzle migrations to production

- [Ops] **db-migrate-production** workflow (manual + on push to `main` when server migrations change) runs `pnpm run -C apps/server db:migrate` with the **`PRODUCTION_DATABASE_URL`** repository secret so `api.todus.app` stays aligned with the repo. Add the same **direct Postgres URL** as the Cloudflare Hyperdrive **origin** (see `docs/development/README.md`). Does not run from this repo alone until the secret is set and the workflow is triggered.
- **Files:** `.github/workflows/db-migrate-production.yml`, `docs/development/README.md`

## [2026-04-25] UX — Docs: clear errors when storage isn’t ready (web + macOS)

- [UX] **Mail + Web:** `DocTree` no longer auto-creates a workspace or stays on skeletons when `docs.workspaces.list` fails (e.g. `PRECONDITION_FAILED` / missing doc tables). Sidebar shows the server message and **Retry**; landing page shows the same message instead of a broken “New page” action.
- [UX] **macOS:** All-docs pane shows **Couldn’t load docs** with the API message and **Retry** when load failed and the list is empty (instead of “No pages yet”). Toolbar **New document** is disabled until a successful refresh when in that error state.
- **Files:** `apps/mail/components/docs/doc-tree.tsx`, `apps/web/components/docs/doc-tree.tsx`, `apps/mail/app/(routes)/mail/docs/page.tsx`, `apps/web/app/(routes)/mail/docs/page.tsx`, `apps/macos/TodusMac/Views/Docs/MacDocsShellView.swift`

## [2026-04-25] Fix — Drizzle migrations run clean on a fresh local database

- [Ops] **Backend:** `0044_pale_luminals.sql` no longer fails on `DROP INDEX "meet_integration_user_id_idx"` or duplicate recall unique blocks from `0043`. `0049_fixed_karma.sql` no longer re-creates assistant/marketing DDL already applied in `0046`–`0048`, so `pnpm db:migrate` completes on an empty DB. Local dev: `createdb todus` (or `psql -c 'CREATE DATABASE todus'`) before migrate; SQL like `CREATE ROLE` must run **inside** `psql`, not the shell.
- **Files:** `apps/server/src/db/migrations/0044_pale_luminals.sql`, `apps/server/src/db/migrations/0049_fixed_karma.sql`

## [2026-04-25] UX — macOS Calendar: Day/Week horizontal scroll in time

- [UX] **macOS:** In **Day** and **Week** views, two-finger **left/right** is easier to trigger over the vertical hour grid (relaxed `adx`/`ady` weight). **Shift + scroll** moves by day/week so the time grid is not also scrolled. Month/Year behavior unchanged.
- **Files:** `apps/macos/TodusMac/Views/Calendar/CalendarTrackpadNavigation.swift`, `apps/macos/TodusMac/Views/Calendar/MacCalendarView.swift`

## [2026-04-25] UX — macOS Calendar week header + all-day row

- [UX] **macOS:** Calendar pane header shows only the month/year title (sidebar app icon removed duplicate mark). Week **all-day** row: label uses a fixed-width `ZStack` so `padding` no longer widens the gutter (day headers + hourly grid + all-day columns align). **all-day** text has no extra background; `calendarAllDayBg` applies only to the day columns, not the label column.
- **Files:** `apps/macos/TodusMac/Views/Calendar/MacCalendarView.swift`

## [2026-04-25] UX — macOS Calendar: trackpad, pinch, keyboard, year view

- [UX] **macOS:** Calendar supports **two-finger horizontal** navigation (faster, lower threshold), **pinch in/out** to change view density (Day ↔ Week ↔ Month ↔ Year), **⌘1–4** to jump view modes, **smoother vertical** month paging (`basedOnSize` bounce), and **year view** that scrolls the selected year into view. The **current calendar month** shows a small **red dot** next to the name. Pointer hit tests use the key window’s `isKeyWindow` to avoid `NSApp` main-actor warnings.
- **Files:** `apps/macos/TodusMac/Views/Calendar/CalendarTrackpadNavigation.swift`, `apps/macos/TodusMac/Views/Calendar/MacCalendarView.swift`, `TASK.md`

## [2026-04-25] Fix — Apple Calendar brand icon (blank white tile)

- [Fix] **Native:** `AppleCalendarLogo` no longer uses `Canvas` + `Path(SVG d)`; Swift’s path parser often returns `nil` for those `d` strings, so the inner art never drew and only the white `AppIconContainer` was visible (Calendar access screen, settings, tab header). The icon is again **layout-based** (red header strip, white “MON”, dark “12”) so it always renders in the inner square. **iOS + macOS:** `BrandIcons.swift` / `MacBrandIcons.swift`.
- [User-facing] Calendar permission, Settings, and calendar tab headers show the full calendar mark again instead of an empty box.

## [2026-04-25] Fix — iOS Calendar tab stuck on “Open Settings” after granting access

- [Fix] **iOS:** Tapping **Allow Access** no longer swaps the UI to **Open Settings** before the system dialog finishes. The Calendar tab’s permission flag now refreshes when `requestAccess()` completes (notification) and when switching to the Calendar tab, not only on app foreground.
- [User-facing] Users who already granted **Full Access** in Settings see the real calendar after connecting; no spurious “open Settings” loop.
- **Files:** `apps/ios/Todus/Todus/Services/Calendar/CalendarService.swift`, `apps/ios/Todus/Todus/Navigation/MainTabView.swift`, `apps/ios/Todus/Todus/Features/Calendar/CalendarPermissionView.swift`, `apps/ios/Todus/status_ios.md`

## [2026-04-25] Fix — Docs: missing DB tables + macOS create affordance

- [Fix] **Backend:** `docs.*` and `docs.workspaces.*` now map Postgres “relation does not exist” for doc tables to `PRECONDITION_FAILED` with a clear message instead of an opaque HTTP 500.
- [UX] **macOS:** Docs shows **New document** in the All docs toolbar, a **+** in the My space header, and a primary **New document** in the empty state; creating surfaces tRPC error text (e.g. migration hint) in an alert. `TodosAPIClient` surfaces tRPC `error.json.message` for failed HTTP responses app-wide.
- [Ops] Production must include doc tables from migration `0044_pale_luminals.sql` (and later doc migrations). Until then, the app explains that Docs storage is not available until migrations are applied.
- **Files:** `apps/server/src/trpc/routes/docs.ts`, `apps/macos/TodusMac/Services/API/TodosAPIClient.swift`, `apps/macos/TodusMac/Services/Docs/MacDocsService.swift`, `apps/macos/TodusMac/Views/Docs/MacDocsShellView.swift`

## [2026-04-25] Fix — Native meetings load with legacy production schema

- [Fix] **Backend:** `meet.listMeetings`, `meet.getMeeting`, `meet.getIntegration`, and calendar sync now tolerate production databases missing newer `mail0_meet_integration` settings/retention columns. The route falls back to the original integration columns with safe defaults and skips retention pruning when retention columns are absent, preventing HTTP 500s in iOS/macOS Meetings.
- [User-facing] Restores the native Meetings page instead of showing "Failed to load meetings. Server error (http 500)."
- **Files:** `apps/server/src/trpc/routes/meet.ts`

## [2026-04-25] Fix — macOS calendar time column (labels + color)

- [Fix] **macOS:** Hour labels disappeared because the foreground gutter used an opaque fill above `hourGridLayer`. The time column is now a clear spacer so labels and tint from `hourGridLayer` show through; `calendarGutterBackground` matches `contentBackground` so the strip is not lighter than the main grid.
- **Files:** `apps/macos/TodusMac/Views/Calendar/CalendarTimeGridView.swift`, `apps/macos/TodusMac/DesignSystem/MacTheme.swift`

## [2026-04-25] Fix — macOS Week calendar column alignment

- [UX] **macOS:** Week view day headers, all-day row, and the scrolling time grid share one measured column width (via `GeometryReader` + `MacTheme.calendarDayColumnWidth`) so columns stay aligned with the day grid. The time-label gutter uses `calendarGutterBackground`; horizontal hour lines only run to the right of that column, not under the stamps.
- **Files:** `apps/macos/TodusMac/Views/Calendar/MacCalendarView.swift`, `apps/macos/TodusMac/Views/Calendar/CalendarTimeGridView.swift`, `apps/macos/TodusMac/DesignSystem/MacTheme.swift`

## [2026-04-25] UX — macOS AI assistant floating panel

- [UX] **macOS:** Floating AI assistant size and position are passed from `MacRootView` (live `@State` + explicit `UserDefaults` sync on move/resize end, mode change, and background) so drags are smooth — no per-frame `AppStorage` writes. Move only from the **title bar strip** (not toolbar buttons): open/closed hand cursors. Resize from **all four edges and corners** (5pt/16pt hit targets) with `resizeUpDown` / `resizeLeftRight` and SF Symbol diagonal cursors; `highPriorityGesture` and disabled layout animation reduce jank.
- [UX] **macOS (earlier in day):** Floating size/position were initially stored in `AppStorage` and passed from `MacRootView` so they survive dock ↔ float. Max float width 800pt.
- **Files:** `apps/macos/TodusMac/App/MacRootView.swift`, `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`

## [2026-04-25] Fix — Native email inbox loads with legacy production schema

- [Fix] **Backend:** Native iOS/macOS mail endpoints now tolerate production databases that have not yet applied the connection color / assistant second-brain migrations. `mail.listThreads` can resolve the active connection without selecting `mail0_connection.color`, multi-connection reads use the same fallback, and `assistant.listOpenLoops` returns an empty nudges list instead of failing when assistant tables are missing.
- [Fix] **Backend:** Bearer-token requests no longer have their real connection error masked by a failed Better Auth sign-out/get-session path.
- [User-facing] Restores native Email Inbox loading instead of showing "Couldn't load Inbox / Failed to load emails."
- **Files:** `apps/server/src/lib/server-utils.ts`, `apps/server/src/trpc/trpc.ts`, `apps/server/src/trpc/routes/connections.ts`, `apps/server/src/trpc/routes/assistant.ts`, `apps/server/src/main.ts`

## [2026-04-25] Fix — iOS Home scroll under tab bar

- [UX] **iOS:** Home dashboard scroll no longer hard-clips at the tab bar. Matches Tasks: `ScrollView` uses `contentMargins(.bottom, 130, for: .scrollContent)` and drops `.clipped()` so content can scroll with the same bottom inset as the Tasks list.
- **Files:** `apps/ios/Todus/Todus/Features/Home/HomeView.swift`

## [2026-04-25] Fix — Apple Calendar icon (iOS + macOS) — superseded

- **Superseded by** the same-day entry **“Fix — Apple Calendar brand icon (blank white tile)”** above: a **Canvas + Path(SVG `d`)** pass for `AppleCalendarLogo` was tried, but Swift’s path parser often yielded `nil`, so the inner art did not draw. The **current** implementation in `BrandIcons.swift` / `MacBrandIcons.swift` is **layout-based** (red header, “MON”, “12”), not Canvas/SVG `d` paths.
- **Files (historical context only):** `apps/ios/Todus/Todus/DesignSystem/BrandIcons.swift`, `apps/macos/TodusMac/DesignSystem/MacBrandIcons.swift`

## [2026-04-25] Fix — Apple Reminders icon (iOS + macOS)

- [UX] **Native:** Replaced the layout-mock Reminders glyph with `Canvas` art matching the Reminders light app icon (1024×1024 coordinates: bars + colored rings). **macOS:** `AppIconContainer` now pins the inner icon to a square and clips like iOS so the glyph no longer crops or bleeds past the white app-icon tile.
- **Files:** `apps/ios/Todus/Todus/DesignSystem/BrandIcons.swift`, `apps/macos/TodusMac/DesignSystem/MacBrandIcons.swift`

## [2026-04-25] Fix — Native Gmail linking uses current app session

- [Fix] Native Gmail linking now sends the app's stored refresh/session token to `/api/auth/native-link-social`, and the backend validates that exact session for the authenticated user before forwarding to Better Auth `link-social`.
- [Fix] This removes the production 401 path where `/api/auth/me` accepted the native JWT but Gmail linking failed with "No active Better Auth session found for account linking."
- **Files:** `packages/swift-auth/Sources/TodusAuth/AuthService.swift`, `apps/server/src/main.ts`

## [2026-04-25] Fix — Native Email OTP sign-in bridge

- [Fix] **Backend:** Added `POST /api/auth/native-email-otp/verify` for iOS/macOS. It validates the existing Better Auth `sign-in` OTP record, creates a native session token, and returns structured JSON errors instead of the opaque empty-body 500 seen from `/api/auth/sign-in/email-otp`.
- [Fix] **Backend:** The native OTP bridge now selects only core auth columns from `mail0_user`, so production logins do not fail if newer app-only user columns have not been migrated yet.
- [Fix] **iOS + macOS:** Shared native `AuthService` now verifies email OTP against the native bridge and captures the returned session ID alongside the raw session token.
- **Files:** `apps/server/src/main.ts`, `packages/swift-auth/Sources/TodusAuth/AuthService.swift`

## [2026-04-24] Feature — Native Docs on macOS (Craft-style shell + bundled Tiptap)

- [Feature] **macOS:** The Docs tab no longer embeds the full web app in `WKWebView` (which could not use native `Authorization` for `clientLoader`). It is now a **native** shell: sidebar (workspaces, tree, starred, new page), **All docs** with grid/list + search, and a full-screen **editor** with title, star, breadcrumb, and a **bundled** Tiptap page loaded from `file://` (`Resources/DocEditor`). Swift injects initial JSON and receives debounced `onUpdate` via `WKScriptMessageHandler` (`todusDoc`); saves go through `docs.*` tRPC. Format strip: bold, italic, H1/H2, lists, task list (JS bridge to `window.todusEditor.run`).
- [Feature] **Backend:** `mail0_doc.is_starred` (default false). `docs.update` accepts optional `parentId`, `workspaceId`, and `isStarred` with workspace ownership checks for moves. Migration `0051_doc_starred_and_move.sql`.
- [Build] **Monorepo:** `packages/macos-doc-editor` builds with esbuild; output is copied to `TodusMac/Resources/DocEditor` for the Xcode bundle. Rebuild after editor changes: `pnpm --filter @zero/macos-doc-editor build` (or the package’s `package.json` name if different).
- [Cleanup] Removed duplicate `TodusMac/MacDocsView.swift` at the `TodusMac` folder root; `MacDocsView` lives under `Views/Docs/`.
- **Files:** `apps/server/src/db/schema.ts`, `apps/server/src/db/migrations/0051_doc_starred_and_move.sql`, `apps/server/src/trpc/routes/docs.ts`, `packages/macos-doc-editor/`, `apps/macos/TodusMac/Resources/DocEditor/`, `apps/macos/TodusMac/Domain/MacDocTypes.swift`, `apps/macos/TodusMac/Services/Docs/MacDocsService.swift`, `apps/macos/TodusMac/Views/Docs/*.swift`, `apps/macos/TodusMac/App/MacAppServices.swift`, `apps/macos/TodusMac.xcodeproj/project.pbxproj`

## [2026-04-25] Fix — macOS: Settings window no longer appears when logged out

- [Fix] **macOS:** The dedicated Settings `Window` used to be **restored at launch** if it had been open when the app quit, so it could reappear next to the sign-in UI. Settings now uses `defaultLaunchBehavior(.suppressed)` (only opens via ⌘, / menu / sidebar). When the login screen is shown or the user signs out, any open Settings window is closed programmatically.

## [2026-04-25] — macOS app icon: Figma full-bleed, light + dark

- [UX] **macOS:** `AppIcon` is regenerated from 1024×1024 Figma (Apple template) sources with one PNG per size slot, **luminosity** `light` / `dark` for system appearance. Masters live under `TodusMac/Resources/AppIconSource/` (not in the asset catalog) for future re-exports. `actool` may still log a known “unassigned children” notice for mac app icons with appearance variants; the archive still produces a valid `AppIcon.icns`.

## [2026-04-25] Feature — iOS AI chat: attachment thumbnails, full-screen preview, vision MIME fix

- [Feature] **iOS:** Sent attachments in the user bubble now show a real image thumbnail (with `loadImage` fallback when thumbnail decode fails) and a short label (“Image”, “Image 2”, or “File (PDF)”) instead of the raw UUID filename. Tap opens a full-screen black preview with **Copy** (image to pasteboard) and **Save** (Photo Library; `NSPhotoLibraryAddUsageDescription` added). Non-image files get **Share** in the same sheet.
- [Fix] **iOS:** `AttachmentService.mimeType` can sniff JPEG/PNG/GIF/WebP magic bytes so the server classifies borderline files as `image/*` and merges them as vision `image_url` parts (matching `mergeAttachmentsIntoLastUserMessage` in `ai.ts`).

## [2026-04-25] Feature — Subscriptions, plan management, and AI usage tracking (web + iOS + macOS + server)

- [Feature] **Backend:** Autumn-based subscriptions wired end-to-end. New users get an Autumn customer with the `free` product on signup. New `subscription` tRPC router exposes `getStatus` / `refresh` / `attach` / `cancel` / `getBillingPortalUrl` / `getPricingTable`.
- [Feature] **Backend:** `mail0_user` cache columns (`plan`, `subscription_status`, `ai_usage_used`, `ai_usage_limit`, `ai_usage_reset_at`) so plan UI renders without an Autumn round-trip per request. Migration `0050_lame_tag.sql`.
- [Feature] **Backend:** AI usage metering. `/api/ai/chat` now (1) blocks with `402 ai_credits_exhausted` when the user is out of credits, (2) requests OpenRouter `stream_options.include_usage`, (3) parses real token counts from the SSE stream, (4) computes USD cost from a per-model rate table, (5) tracks the cost as `ai_usage` credits in Autumn (1 credit = $1) — fire-and-forget so tracking failures never affect chat.
- [Feature] **Backend:** Public webhook handler at `POST /webhooks/autumn` with HMAC-SHA256 signature verification (`AUTUMN_WEBHOOK_SECRET`). Refreshes the cached subscription state for the affected customer on any Autumn event.
- [Feature] **Web:** New `/settings/billing` page with current plan, AI usage progress bar, manage / upgrade / cancel buttons, and warnings at 80% / 100% utilization. Sidebar entry added.
- [Feature] **Web:** Pricing card now uses real product IDs (`pro_monthly` / `pro_annual`); upgrade flow opens Stripe Checkout via Autumn.
- [Feature] **iOS:** `SubscriptionService` (cached read of plan + AI usage). New `BillingSettingsView` with manage-billing and cancel actions; nav entry added under Settings → Subscription. Free users get an "Upgrade to Pro" link out to the web pricing page (Apple's external-link policy).
- [Feature] **macOS:** `MacSubscriptionService` and a new `billingSection` on `MacSettingsView` mirroring the iOS UI: plan summary, credit progress bar, manage/cancel/upgrade. Opens billing portal via `NSWorkspace`.
- [Files] `apps/server/src/db/schema.ts`, `apps/server/src/lib/billing.ts`, `apps/server/src/lib/ai/model-pricing.ts`, `apps/server/src/trpc/routes/subscription.ts`, `apps/server/src/routes/autumn-webhook.ts`, `apps/server/src/routes/ai.ts`, `apps/server/src/lib/auth.ts`, `apps/server/src/main.ts`, `apps/server/src/env.ts`, `apps/server/src/trpc/index.ts`, `apps/server/src/db/migrations/0050_lame_tag.sql`, `apps/mail/app/(routes)/settings/billing/page.tsx`, `apps/mail/app/routes.ts`, `apps/mail/config/navigation.ts`, `apps/mail/components/pricing/pricing-card.tsx`, `apps/mail/components/ui/nav-user.tsx`, `apps/mail/hooks/use-billing.ts`, `apps/mail/lib/utils.ts`, `apps/ios/Todus/Todus/Services/Subscription/SubscriptionService.swift`, `apps/ios/Todus/Todus/Features/Settings/BillingSettingsView.swift`, `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`, `apps/ios/Todus/Todus/App/AppServices.swift`, `apps/macos/TodusMac/Services/Subscription/MacSubscriptionService.swift`, `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`, `apps/macos/TodusMac/App/MacAppServices.swift`
- [Manual steps required] Run `pnpm db:push` (or `pnpm db:migrate` in prod) to apply migration `0050_lame_tag.sql`. Set `AUTUMN_SECRET_KEY` (already done by user). Once the webhook setting is found in the Autumn dashboard, set `AUTUMN_WEBHOOK_SECRET` via `wrangler secret put` and point Autumn at `https://api.todus.app/webhooks/autumn`.

## [2026-04-25] Feature — Paste images and files into AI chat (iOS + macOS + web)

- [Feature] **iOS:** Clipboard paste in the AI composer now supports photos (unchanged) plus non-image files via `NSItemProvider` (file URL, images, PDF, generic data) saved through `AttachmentService` and added to the pending-attachment row.
- [Feature] **macOS:** `MacChatNSTextView` intercepts paste to add `NSImage` (written to a temp PNG), file URLs from Finder, or raw PNG/TIFF/PDF data from the pasteboard to `pendingAttachments` (same path as the + attach button).
- [UX] **macOS:** Pending attachment row scrolls horizontally when crowded; each pill shows a 22px image preview (for image types), truncated name, uppercase format label, remove control, and drops paste temp files on remove.
- [Feature] **Web** (`apps/mail` + `apps/web` mail chat): Pasting files or images into the assistant textarea queues them (removable chips), sends with `useChat` `append` + `experimental_attachments` (data URLs), and shows attached filenames on user bubbles when present.
- **Files:** `CaptureComposer.swift`, `AIChatView.swift`, `MacAssistantPanel.swift`, `apps/mail/.../mail/chat/page.tsx`, `apps/web/.../mail/chat/page.tsx`

## [2026-04-25] Fix — Toggle visibility (iOS + macOS)

- [Fix] `Toggle` / switch controls no longer use `.tint(.primary)` (which could render as white-on-white in dark mode). Shared tokens `AppTheme.switchTint` and `MacTheme.switchTint` use system blue so the on-state is visible in light and dark mode.
- **Files:** `AppTheme.swift`, `MacTheme.swift`, `SettingsView.swift` (incl. AI Assistant sub-list), `AIChatView.swift`, `RemindersSetupView.swift`, `TaskDetailSheet.swift`, `SignaturesView.swift`, `MacSettingsView.swift`, `MacTasksView.swift`

## [2026-04-25] Fix — iOS Gmail OAuth connection flow

- [Fix] iOS Gmail onboarding now uses the Gmail link-social flow instead of auth-only Google sign-in, so the OAuth redirect grants mail scopes and creates the backend connection row before the app marks Gmail as configured.
- [Fix] iOS onboarding, empty-mail connect, and Settings now share `EmailService.connectGmail`, including forced connection polling while Better Auth account hooks persist the connection.
- [Fix] Shared native auth ignores `todus://link-callback` if it is delivered through app URL handling, avoiding a false "Sign-in failed" state after a successful link-social OAuth flow on iOS/macOS.
- **Files:** `apps/ios/Todus/Todus/Services/Email/EmailService.swift`, `apps/ios/Todus/Todus/App/GmailOnboardingView.swift`, `apps/ios/Todus/Todus/Features/Email/EmailConnectView.swift`, `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`, `packages/swift-auth/Sources/TodusAuth/AuthService.swift`

## [2026-04-25] Hardening — AI chat reliability across all actions (iOS + macOS + server)

- [Fix] **macOS calendar update/delete were unreachable from chat.** `refreshCalendarSnapshot` now embeds each event's identifier as `[<id>]` next to the title and tells the model to pass it back as `id` to `update_calendar_event` / `delete_calendar_event`. Without this the model had no handle to target an existing event.
- [Fix] **Follow-up tool steps no longer waste resources or confuse providers.** When iOS/macOS re-call `/api/ai/chat` with `tool` role messages from the previous step, the server now skips mention enrichment, web-search heuristics, and attachment merging (those only apply to the original user turn). The clients also drop `attachments` and `mentions` from follow-up payloads.
- [Fix] **`assistant_with_tool_calls` content normalization.** iOS and macOS now send `content: nil` (omitted) instead of `content: ""` when an assistant message exists only to carry tool calls. Some providers reject empty-string content paired with `tool_calls`, which manifested as silent failures mid-loop.
- [Fix] **Voice tool guards no longer conflate failure modes.** `create_calendar_event`, `update_calendar_event`, `delete_calendar_event`, and `send_email` in the voice tool path now use a per-condition guard chain (permission → args decode → ISO date parse → service availability → execute) matching the text-chat path, so users get a precise error instead of a generic "couldn't do that".
- **Files:** `apps/server/src/routes/ai.ts`, `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`, `apps/macos/TodusMac/Services/AI/MacAIChatService.swift`
- **Verified:** Debug builds pass on both iOS and macOS targets.

## [2026-04-25] Fix — AI chat silent on tool-only responses (iOS + macOS)

- [Fix] AI chat ("Ain") now responds correctly when the model emits only `tool_calls` in its first SSE round (e.g. "create a reminder", "schedule a meeting"). Previously the assistant bubble was empty because (a) fragmented `tool_calls` deltas were rejected by a strict SSE schema, and (b) tool results were never sent back to the model for a natural-language confirmation.
- [Fix] `SSEToolCall` fields (`index`, `id`, `function`) are now optional and accumulated across deltas keyed by `index`, matching the OpenAI streaming protocol.
- [Fix] Streaming is wrapped in a multi-step agent loop (max 5 iterations): if a step returns tool calls, they are executed and the results are appended as `tool` role messages plus an `assistant_with_tool_calls` message before re-calling the model. The model then produces user-visible confirmation text.
- [Fix] If the loop completes without any visible content, a fallback "Done." message is appended so the bubble is never empty.
- [Fix] Server `chatMessageSchema` uses `.passthrough()` and explicitly accepts `tool_calls`, `tool_call_id`, and `name` so the multi-step protocol can round-trip through OpenRouter without zod stripping fields.
- [Feature] iOS + macOS chat now declares `update_calendar_event` and `delete_calendar_event` tools alongside `create_calendar_event`, and includes execution handlers backed by `CalendarService.updateEvent` / `deleteEvent`.
- **Files:** `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`, `apps/macos/TodusMac/Services/AI/MacAIChatService.swift`, `apps/server/src/routes/ai.ts`

## [2026-04-25] Fix — Native auth refresh token compatibility

- [Fix] `/api/auth/refresh-native-token` now accepts both native refresh-token formats during the transition: bearer-plugin tokens from `set-auth-token` and the raw Better Auth session token returned by `/auth/mobile-token`.
- [Fix] If bearer resolution fails, the server rehydrates the raw session token as a signed Better Auth cookie before minting a fresh JWT, so existing iOS/macOS sessions keep refreshing instead of expiring after the first 15-minute access-token window.
- [Fix] `NoRedirectDelegate` now stops at the first redirect for native auth bridge requests, so Gmail linking, Apple sign-in, and OTP fallback flows can inspect the original 3xx `Location` / cookie headers instead of silently following the redirect and losing them.
- **Files:** `apps/server/src/main.ts`, `packages/swift-auth/Sources/TodusAuth/NoRedirectDelegate.swift`

## [2026-04-24] Feature — Home proactive AI suggestions (iOS + macOS)

- [Feature] Home shows a **Suggestions for you** strip powered by existing open-loop nudges (`EmailService.loadAssistantNudges` / assistant inbox nudges): short explainer, horizontal cards, tap opens the thread or Mail when no thread id.
- [UX] macOS: section respects Focus Mode (`mac_focus_mode_enabled`) and matches the editorial card styling; iOS: section after the greeting, before the briefing block.
- [Fix] macOS: replaced invalid `MacTheme.spacing10` references with `spacing8` so the target compiles.

## [2026-04-24] UX — pointer cursor for interactive controls (web + macOS)

- [UX] Web (`apps/web`, `apps/mail`): base styles now set `cursor: pointer` for native `checkbox` / `radio` / `file` / `range` inputs and for labels that wrap a checkbox or radio; existing rules already covered `button`, links, and ARIA roles.
- [UX] macOS: added `macClickablePointer()` (`PointerStyle.link`) and applied it across toolbars, settings, email/meetings/create flows, the AI panel, and other plain-style buttons; regenerated `TodusMac.xcodeproj` so `MacClickablePointer.swift` is included in the target.

## [2026-04-24] UX — iOS & macOS: icon tint is primary, not system blue

- [UX] Tab bar, toggles, lists, and AI chrome that used `Color.blue` or a blue accent now use `Color.primary` / primary text so SF Symbols and labels match the monochrome editorial look. macOS root `.tint` is `Color.primary` (the in-app accent picker no longer tints the whole shell).
- [UX] Group/shared chat and share CTAs that used “white on near-primary” were adjusted to primary-on-subtle fill so dark mode keeps readable contrast.
- **Files:** `AppTheme.swift` (`accentBlue`), `MainTabView.swift` (via token), `MacRootView.swift`, and affected feature views under `apps/ios/Todus` and `apps/macos/TodusMac`.

## [2026-04-24] Fix — OAuth mailbox identity + iOS voice tool parity

- [Fix] `syncConnectionFromAccount` now resolves the connected mailbox from the OAuth account itself instead of `mail0_user.email`, which fixes multi-account Google linking/reconnect flows that were overwriting the wrong connection email/token pair.
- [Fix] Provider identity fallback is now provider-aware: Google uses `id_token` / OIDC userinfo, while non-Google providers fall back to the driver `getUserInfo()` path instead of calling Google endpoints with the wrong token type.
- [Fix] Connection expiry now stores the provider's actual `accessTokenExpiresAt` timestamp instead of adding that absolute timestamp to `Date.now()`, which previously pushed some connection expiry values decades into the future.
- [Fix] iOS voice chat now exposes the same supported task/calendar tool contract as text chat: removed unsupported `urgent` task priorities from voice tool schemas and added calendar update/delete tool declarations plus execution handlers.
- [Fix] iOS voice input stop-timeout now uses the latest partial transcript at timeout time instead of the stale transcript captured when the user tapped stop, so trailing words are no longer dropped when the recognizer final callback arrives late.
- **Files:** `apps/server/src/lib/auth.ts`, `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`, `apps/ios/Todus/Todus/Features/Voice/VoiceInputButton.swift`

## [2026-04-24] Fix – tRPC HTTP endpoint prefix (404 on native + web)

- [Fix] Set `@hono/trpc-server` `endpoint` to `/api/trpc` so `fetchRequestHandler` strips the full pathname correctly (`/api/trpc/meet.listMeetings` → `meet.listMeetings`). The previous `/trpc` value left a `trpc/...` remainder and all procedures returned **HTTP 404**.
- **File:** `apps/server/src/main.ts`

## [2026-04-24] Fix — macOS app icon matches iOS

- [UX] macOS Dock: naive scaling of a **rect** crop around the mark kept **white in the rect corners** (between glyph arms and the crop edge), so the icon still looked like a smaller sharp-edged white square on the system plate. The compose script now **floods** edge-connected “paper white” to **transparent**, keeps ink + **enclosed** counter whites, scales that blob to **~95%** of 1024, and writes `AppIcon-macos-master.png` + all `AppIcon.appiconset` sizes (`compose-macos-app-icon.py`).
- [Fix] Regenerated the macOS `AppIcon` asset (all sizes in `AppIcon.appiconset` plus `AppIcon.icns`) from the same 1024×1024 source as the iOS app (`App-Icon-1024x1024@1x.png`); the Dock had been showing the generic placeholder when those assets were outdated or mismatched.
- [Config] `Info.plist`: set `CFBundleIconName` to `AppIcon` so the bundle resolves the asset-catalog icon set reliably.
- [Build] Stopped bundling a duplicate `AppIcon.icns` as a resource; `actool` already emits the app icon from `Assets.xcassets`, and the extra copy could race and fail the build.

## [2026-04-24] Fix — Meetings API aligned with native apps

- [Fix] `meet.listMeetings` now returns `total` (and normalizes `actionItems` to `{ task, owner, dueDate }` so AI `description` fields decode on iOS/macOS). Inputs accept JSON `null` for optional fields (Swift encoders send null; Zod previously rejected them).
- [Fix] `meet.getMeeting` returns a single flat payload with `transcript` and `media`, matching `MeetingDetailResponse` on native clients; web/mail meeting detail pages updated accordingly.
- [Fix] `meet.scheduleBot` includes `success: true` for the native `ScheduleBotResponse` type; `SyncResponse` on iOS/macOS now matches `syncFromCalendar` (`synced`, `total`, `autoRecorded`).

## [2026-04-24] Feature — Task board: macOS drag-and-drop + iOS parity

- [Feature] macOS Tasks board: drag tasks between columns to update `TaskStatus`, persist with `syncState` pending upload, and highlight the drop target; horizontal scroll when columns do not fit.
- [UX] iOS Tasks board: column chrome and cards aligned with the macOS kanban (uppercase stage labels, count badge, row-style cards with status icon, due/priority/folder meta, trailing chevron); shared short due-date formatter.
- [Fix] iOS AI chat: attachment file chip used a non-existent `AppTheme.surfaceCard` token — use `surfacePrimary` so the target builds.
- **Files:** `apps/macos/TodusMac/Views/Tasks/MacTasksView.swift`, `apps/ios/Todus/Todus/Features/Tasks/BoardColumnView.swift`, `BoardTaskCard.swift`, `DesignSystem/Formatters.swift`, `Features/AI/AIChatView.swift`

## [2026-04-24] Feature — macOS Tasks: Reminders + onboarding

- [UI] Tasks toolbar: removed per–view-mode hint text and the “completed tasks in List” note; segmented control track now uses a `Capsule` so the outer chrome matches the inner pills.
- [Feature] “Connect Apple Reminders” on the Tasks page and a new onboarding step (step 3 of 4) after Calendar, aligned with iOS; EventKit sync uses the same flow as iOS (import + push existing tasks).
- [Feature] Connected Services “Connect” for Apple Reminders now requests Reminders permission instead of only toggling a flag; added Reminders entitlement and `NSRemindersUsageDescription`.
- [Migration] Users who already finished startup onboarding before this release skip the new Reminders screen once.

## [2026-04-24] Fix — Native AI chat file attachments (iOS, macOS, server)

- [Fix] Chat attachments are now serialized (base64 + MIME) in the `POST /api/ai/chat` body and merged into the last user turn on the server: images use OpenAI-style `image_url` parts; text-like files are inlined; other binaries get a short description so the model can still reason from filename and context.
- [Fix] iOS: pending files are read from `AttachmentService` storage, `send` accepts `attachmentFileNames`, and user bubbles show attachment pills next to the message. Saved conversations persist attachment filenames (re-open shows labels; re-sending from disk works when files still exist).
- [Fix] macOS: file picker URLs are read with security-scoped access, payloads cached by user message id for the stream/ retry round, the send button enables for attachment-only sends, and user bubbles list attached file names.
- **Files:** `apps/server/src/routes/ai.ts`, `apps/ios/.../AIChatView.swift`, `AIChatService.swift`, `AIChatMessage.swift`, `AIChatConversation.swift`, `AttachmentService.swift`, `EmailAIDraftSheet.swift`, `apps/macos/.../MacAIChatService.swift`, `MacAssistantPanel.swift`

## [2026-04-24] Polish — macOS scrollbars

- [UI] macOS app now uses overlay scroll indicators: no track well, slim floating thumb that appears while scrolling and fades when idle; `NSScrollView` backgrounds are cleared so no strip shows behind the thumb.
- [UI] Follow-up: clear `NSClipView` backgrounds and re-apply chrome on layout for SwiftUI `ScrollView`s (AI assistant + group chat); in-scroll `MacScrollViewChromeAnchor` + `NSScroller` small control size; composer `NSTextView` scroll view uses shared `applyChrome`.
- **Files:** `apps/macos/TodusMac/DesignSystem/MacScrollStyle.swift`, `apps/macos/TodusMac/App/TodusMacApp.swift`, `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`, `apps/macos/TodusMac/Views/AI/MacGroupChatView.swift`

## [2026-04-24] Fix — iOS voice chat WebSocket route interception

- [Fix] Scoped the server tRPC middleware to `/trpc/*` inside the `/api` sub-app and corrected its endpoint to `/trpc`, so `/api/ai/voice-ping` and `/api/ai/voice-ws` now reach the AI router instead of being misparsed as tRPC procedure paths.
- [Fix] This restores the iOS voice-chat WebSocket upgrade path that was surfacing as `NSURLErrorDomain Code=-1011` / “There was a bad response from the server.”
- [Architectural] The regression was in backend route registration, not the iOS audio stack: the broad tRPC middleware was shadowing sibling `/api/ai/*` routes after the `/api` mount.
- [Fix] iOS voice chat now refreshes an expiring native bearer token before starting the WebSocket handshake, so the voice session no longer fails with a `401` upgrade when the app is otherwise still signed in.
- **Files:** `apps/server/src/main.ts`

## [2026-04-24] Fix — iOS AI chat composer focus (keyboard / + button)

- [Fix] Removed a `ScrollView` `simultaneousGesture` that resigned the keyboard on every tap; that gesture also hit-tested the bottom `safeAreaInset` input row, so taps on the text field, padding, or the + button dismissed the keyboard and interfered with double-tap-to-copy on messages.
- [Fix] The full-screen clear tap layer now only appears for the attachment picker (not while the field is focused); the input box uses a `simultaneousGesture` tap to request focus without stealing the UITextView’s first touch.
- [Fix] The + attachment source popover can be dismissed by tapping outside it: a dimming scrim is applied in `.overlay` above the message/empty content _before_ `.safeAreaInset`, so it receives taps (unlike a `ZStack` layer behind the chat) and does not cover the input bar or popover.
- **Files:** `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`

## [2026-04-24] Fix — iOS Gmail connect flow + backend fallback for schema drift

- [Fix] Native iOS Gmail linking now requests a non-redirecting Better Auth OAuth URL, uses the correct `/api/auth/native-link-social` endpoint, and opens the returned Google consent URL in `ASWebAuthenticationSession` instead of trying to decode a followed redirect as JSON.
- [Fix] Added an explicit `ASWebAuthenticationSession.start()` failure path so the app no longer silently stalls when the system cannot launch the web auth session.
- [Fix] `connections.list` now falls back to a legacy raw query when the deployed database is missing `mail0_connection.color`, which restores Gmail connection checks and the connections UI on older schemas.
- [Fix] `sessions.list` now degrades gracefully when `mail0_session_metadata` is missing, returning active sessions without device/location enrichment instead of a 500.
- [Fix] `assistant.getBriefing` now returns a task-only fallback briefing when the deployed database is missing `meeting` or assistant tables, preventing the startup 500 seen in iOS logs.
- [Architectural] These backend fallbacks are compatibility shims for environments where production code is ahead of applied Drizzle migrations; they keep user-facing surfaces working while the database is brought up to date.
- **Files:** `packages/swift-auth/Sources/TodusAuth/AuthService.swift`, `apps/server/src/trpc/routes/connections.ts`, `apps/server/src/trpc/routes/sessions.ts`, `apps/server/src/trpc/routes/assistant.ts`

## [2026-04-13] Fix — Frontend Vite tsconfig path resolution

- [Fix] Scoped `vite-tsconfig-paths` in the frontend Vite configs to each app's local `tsconfig.json` so builds no longer crawl `apps/archived` and `reference/` configs that are outside the active app.
- [Build] Removed the noisy `TSConfckParseError` warnings caused by missing legacy/reference tsconfig dependencies during `pnpm --filter=@zero/mail build`.
- [Architectural] Kept the change surgical by fixing only Vite path-resolution scope; no route, runtime, or UI behavior changed.
- **Files:** `apps/mail/vite.config.ts`, `apps/web/vite.config.ts`

## [2026-04-08] Feature — Ollama integration + AI model selector

- [Feature] Added user-facing AI provider/model selector in the chat sidebar header (compact) and a full AI settings page at `/settings/ai`.
- [Feature] Users can now select from OpenAI, Anthropic, Google, Groq, OpenRouter, or Ollama (local) as their AI provider.
- [Feature] Ollama integration: list installed models, pull new models with progress, delete models, connection status indicator, CORS troubleshooting help.
- [Feature] Added `aiProvider`, `aiModel`, and `ollamaBaseUrl` to user settings schema.
- [Refactor] Created centralized `ai-model-resolver.ts` — single source of truth for model construction across all backend endpoints.
- [Refactor] Replaced hardcoded `openai(...)` calls in 10+ backend files with the resolver.
- [UI] New settings nav item "AI & Models" with Cpu icon.
- **New files:** `ai-model-resolver.ts`, `model-selector.tsx`, `use-ollama.ts`, `ollama-utils.ts`, `settings/ai/page.tsx`
- **Modified files:** `schemas.ts`, `agent/index.ts`, `ai-sidebar.tsx`, `ai-chat.tsx`, `routes.ts`, `navigation.ts`, `compose.ts`, `search.ts`, `chat.ts`, `ai.ts`, `tools.ts`, `interests.ts`, `groups.ts`, `meet.ts`

## [2026-04-08] Refactor — Adopt centralized AI model resolver across backend

- [Refactor] Replaced direct `openai(...)` model construction calls with the centralized `resolveModel()` / `resolveModelFromSettings()` from `ai-model-resolver.ts` in five backend files.
- [Refactor] `search.ts` uses `resolveModelFromSettings()` since it already loads user settings, enabling per-user provider selection.
- [Refactor] `compose.ts`, `interests.ts`, `groups.ts`, and `meet.ts` use `resolveModel({ provider: 'auto', ... })` which preserves the existing env-var cascade (OpenRouter -> Google -> OpenAI -> Anthropic).
- **Files:** `apps/server/src/trpc/routes/ai/compose.ts`, `apps/server/src/trpc/routes/ai/search.ts`, `apps/server/src/lib/analyze/interests.ts`, `apps/server/src/trpc/routes/groups.ts`, `apps/server/src/trpc/routes/meet.ts`

## [2026-04-06] Fix — Missing Database Columns for meeting settings

- [Fix] Fixed an issue where the `meetIntegration` table in `db/schema.ts` was missing several columns (such as `auto_delete_days`, `last_pruned_at`, `auto_generate_summary`, etc.) that were being queried by the backend meetings endpoints, which resulted in a crash under `meet.listMeetings`.
- [Build] Generated a new Drizzle migration (`0049_fixed_karma.sql`) and pushed to the local database to apply the missing columns.
- **Files:** `apps/server/src/db/schema.ts`

## [2026-04-06] UX — Removed "Add Task" buttons from Tasks page (iOS)

- [UX] Removed the "Add Task" button from the `TasksTabView` header to declutter the main task interface.
- [UX] Removed the "Add Task" buttons and plus icons from the `BoardView` columns (headers and footers) to simplify the board layout.
- [UX] Removed the tap-to-add gesture from board columns.
- [UX] Updated empty state messaging in both List and Board views to guide users towards the central "Create" button in the tab bar or dragging existing tasks.
- **Files:** `apps/ios/Todus/Todus/Features/Tasks/TasksTabView.swift`, `apps/ios/Todus/Todus/Features/Tasks/BoardColumnView.swift`, `apps/ios/Todus/Todus/Features/Tasks/InboxView.swift`

## [2026-04-06] Fix — iOS CreateSheet Floating Position

- [Fix] iOS `CreateSheet`: Added `.ignoresSafeArea(.container, edges: .bottom)` to the main `ZStack` so it properly ignores the safe area inset injected by `MainTabView`. This fixes the issue where the input UI was pushed to the top of the screen by double-counting the safe area and keyboard height.
- **Files:** `apps/ios/Todus/Todus/Navigation/CreateSheet.swift`

## [2026-04-04] Fix — macOS Xcode target graph for shared auth

- [Build] Fixed the macOS Xcode project so shared auth sources resolve from `packages/swift-auth/Sources/TodusAuth` instead of the stale removed `apps/swift-auth` path.
- [Build] Removed the placeholder `App/ConnectionsService.swift` from the macOS target graph and kept the real `Services/ConnectionsService.swift` as the only compiled source.
- [Verification] Confirmed `xcodebuild -project apps/macos/TodusMac.xcodeproj -scheme TodusMac -configuration Debug -derivedDataPath /tmp/todusmac-derived CODE_SIGNING_ALLOWED=NO build` succeeds locally.
- **Files:** `apps/macos/project.yml`, `apps/macos/TodusMac.xcodeproj/project.pbxproj`

## [2026-04-04] Feature — Unread dot repositioned + People view mode + avatar fixes

### Unread indicator moved to right of subject (iOS, macOS, Web)

- [UI] Moved blue unread dot from left of avatar to right of subject line across all platforms
- Emails now stretch correctly without the left-side dot misaligning the avatar column
- **Files:** `EmailRowView.swift`, `MacEmailInboxView.swift`, `mail-list.tsx`

### People view mode (iOS, macOS)

- [Feature] Added Threads/People toggle in inbox header (icon-based segmented control)
- People mode groups emails by sender — shows avatar, name, email, thread count, unread badge
- Tapping a person shows their threads (iOS: push navigation, macOS: detail panel)
- **Files:** `EmailInboxView.swift`, `MacEmailInboxView.swift`

### Avatar transparent background fix + fallback priority

- [Fix] iOS/macOS: White background behind loaded avatar images prevents colored initials bleeding through transparent logos
- [Fix] All platforms: Google favicon service prioritized in local fallback chain for better icon coverage
- **Files:** `SenderAvatarView.swift`, `MacEmailInboxView.swift`, `bimi-avatar.tsx`

## [2026-04-04] Fix — Inbox People view polish, thread AI timestamp, French grammar

- [Enhancement] iOS `EmailInboxView`: Extracted `buildSenderGroups(from:)`; view mode control exposes VoiceOver labels + selected state; People/threads UI unchanged (already wired).
- [Fix] iOS `EmailThreadView`: Summary attribution line uses `assistantContextLoadedAt` (set when assistant context loads) instead of `Date()` on every render.
- [i18n] `fr.json`: Corrected broken elisions (`d'courriel` → `de courriel`, etc.) and send-failure / shortcuts strings.
- **Files:** `EmailInboxView.swift`, `EmailThreadView.swift`, `apps/mail/messages/fr.json`

## [2026-04-04] Fix — Compose recipients, AI draft sheet, French locale, photo picker

- [Fix] iOS `EmailComposeView`: To field clears to `[]` when empty (matches CC/BCC); Photos picker resets selection after load, surfaces load/decode failures (alert + `AppLogger`), no silent `try?`.
- [Enhancement] iOS `EmailAIDraftSheet`: Replace vs append explicit (`EmailAIDraftInsertMode`); cancel streaming on sheet dismiss; `URLRequest` timeout 30s; `Origin` from `AppConfiguration.effectiveAppURL` (not hardcoded).
- [i18n] `apps/mail/messages/fr.json`: Standardized user-facing strings to **courriel** / **pourriel** terminology.
- **Files:** `EmailComposeView.swift`, `EmailAIDraftSheet.swift`, `apps/mail/messages/fr.json`

## [2026-04-04] Fix — Sender avatar transparent background bleed-through + fallback priority

- [Fix] iOS/macOS: Added white background circle behind loaded avatar images so transparent logos (Slack, GitHub, etc.) no longer show the colored initials circle bleeding through behind them
- [Fix] iOS/macOS/Web: Reordered local favicon fallback chain to prioritize Google's favicon service (`s2/favicons?sz=128`) — same source Gmail uses, highest coverage — before direct `/apple-touch-icon.png` and `/favicon.ico` fetches
- **Files:** `apps/ios/Todus/Todus/Features/Email/SenderAvatarView.swift`, `apps/macos/TodusMac/Views/Email/MacEmailInboxView.swift`, `apps/mail/components/ui/bimi-avatar.tsx`

## [2026-04-04] Fix — iOS AI chat: input height, user bubble roundness, AI paragraph spacing

- **Input height reduced:** Tightened padding in `chatInputBox` — text field top/bottom padding reduced, button row bottom padding reduced, pill row padding reduced. Input is now more compact.
- **User bubbles more round:** Increased corner radius from 16 → 20 and reduced vertical padding from 12 → 10. Single-line messages now appear capsule/pill-shaped (cornerRadius ≈ height/2).
- **AI paragraph spacing:** Added 6pt `paragraphSpacing` via `NSParagraphStyle` to the markdown `AttributedString`. SwiftUI's `Text` has no default gap between CommonMark paragraphs, making AI responses appear as a single blob. This preserves heading-specific paragraph styles via `enumerateAttribute`.

**Files:** `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`

## ⚠️ Build Status

- Overall: Targeted second-brain surfaces are green. The web assistant files were checked with targeted TypeScript verification, and both native apps build successfully after the latest assistant + target-graph fixes.
- Blocking: None for the second-brain scope documented below.
- Informational: Per-file verification details belong in CI logs instead of duplicated release notes.

## [2026-04-04] iOS Email Thread View — Readability, Performance & Summary UX

- [Fix] Dark mode email readability: universal `* { background-color: transparent !important }` CSS override strips all inline/HTML backgrounds in WKWebView; JS post-load strips `bgcolor` HTML attributes; forces all text to `#e0e0e0` in dark mode so emails are always readable (`EmailThreadView.swift`)
- [Fix] Performance: email body shows plain text instantly on expand, defers WKWebView HTML rendering by 150ms to avoid 3-5 second UI hang (`EmailThreadView.swift`)
- [Enhancement] Summary card: "Not summarized yet" with outlined "Summarize" button (gradient sparkles icon, muted stroke, no fill) triggers on-demand summarization; shows actual error message on failure (`EmailThreadView.swift`, `EmailService.swift`)
- [Enhancement] Header background: pure gradient fade (no solid fill), starts at 0.9 opacity and fades to transparent — content smoothly fades under the bar (`EmailThreadView.swift`)
- [Fix] Bottom reply bar: removed solid `backgroundTop` fill behind buttons, replaced with single smooth gradient that extends 30pt above the buttons — no more harsh cutoff (`EmailThreadView.swift`)
- [Fix] Added `loadAssistantThrowing` to `EmailService` so Summarize button can surface real error messages instead of generic "Could not generate summary" (`EmailService.swift`)

## [2026-04-04] iOS CreateSheet Input Polish

- [Fix] Capped `PasteHandlingTextInput` at `maxHeight: 120` in `CreateSheet` — eliminates unbounded layout growth that caused lag and the sheet appearing too tall (`CreateSheet.swift`, `CaptureComposer.swift`)
- [Fix] Removed helper copy ("Write naturally. Todus will sort it.") — sheet is now compact like the AI chat input (`CreateSheet.swift`)
- [Fix] Fixed placeholder-below-cursor bug: `textViewDidBeginEditing` now calls `invalidateIntrinsicContentSize()` + `setContentOffset(.zero)` after clearing placeholder text (`CaptureComposer.swift`)
- [Fix] Keyboard positioning uses `max(keyboard.height + 8, 86)` instead of conditional — removes redundant layout pass when keyboard height changes (`CreateSheet.swift`)

## [2026-04-04] Localization and Native UX Follow-Up

### iOS (`apps/ios/Todus`)

- **Touch target documentation:** Clarified that `minTouchTarget()` enforces a visible minimum 44x44 frame and then expands the hit target further, so the comment now matches the actual modifier behavior.

### macOS (`apps/macos`)

- **Connection filter recovery:** When removed accounts invalidate the previously enabled set, the macOS connections service now re-enables the remaining current connections instead of leaving the app with an empty enabled set.

### Web (`apps/mail`)

- **Locale cleanup:** Updated targeted Arabic, Spanish, Hungarian, Korean, Czech, French, Catalan, Latvian, English, and Polish message keys for missing translations, terminology consistency, tone consistency, and review-friendly JSON formatting where requested.
- **Translation key normalization:** Standardized `favorites` and `failedToSaveLabel` message keys across the locale catalog, aligned the Arabic bin label with existing trash copy, removed accidental Catalan newline padding, and added the missing Polish `many` plural form for note counts.

### macOS (`apps/macos`)

- **Project portability:** Replaced the hardcoded Swift-auth source path in the Xcode project with a relative reference, removed the duplicate `ConnectionsService.swift` compile entry, and set a concrete default build configuration.

## [2026-04-04] Web App Catch-Up Sync — Mirror `apps/mail` into `apps/web`

### Web (`apps/web`)

- **Canonical source restored:** Synced the newer web-facing changes that had been applied in `apps/mail` over to `apps/web`, while intentionally leaving `apps/mail` unchanged.
- **Route parity:** Brought `apps/web` up to date with the newer route/layout surface from `apps/mail`, including docs, meetings, sharing, and group-join/chat related pages.
- **UI parity:** Mirrored the latest mail/home/tasks/search/settings/navigation/sidebar/thread-view updates so `apps/web` matches the newer app behavior and information architecture already present in `apps/mail`.
- **Multi-account and refresh UX parity:** Carried over the connection filter provider, background refresh indicator, optimistic cache/task updates, and related mailbox/thread rendering changes that had diverged.
- **Translations:** Synced the localized message catalogs that the newer web surfaces depend on.

### Verification

- `pnpm --filter @zero/web build` [Passed]

## [2026-04-04] Multi-Account Support — Backend, Web, iOS, macOS

### Backend (`apps/server`)

- **Schema:** Added `color` column to `connection` table (migration `0047_connection_color.sql`) for per-account visual differentiation.
- **Middleware:** New `multiConnectionProcedure` in `trpc.ts` that resolves ALL user connections (not just default) for multi-account endpoints.
- **`mail.listThreadsMulti`:** New endpoint that fetches threads from multiple connections in parallel, merges and sorts by date, returns threads tagged with `connectionId/connectionEmail/connectionColor`, handles partial failures gracefully.
- **`calendar.eventsMulti`:** New endpoint that fetches calendar events from all Google connections in parallel, merges and sorts by start time.
- **`connections.updateColor`:** New mutation to update a connection's display color.
- **`connections.list/getDefault`:** Now includes `color` field in response (auto-assigned from palette if not set).

### Web (`apps/mail`)

- **ConnectionFilterProvider:** New React context (`providers/connection-filter-provider.tsx`) managing which connections are visible, persisted to localStorage. Default: all enabled.
- **nav-user.tsx:** Evolved account avatars from click-to-switch to click-to-toggle-visibility. Each account shows a colored ring (connection color) when enabled, reduced opacity when hidden. Right-click context menu for "Set as default". Star icon on default account.
- **use-threads.ts:** Updated to call `listThreadsMulti` when multiple connections are enabled (unified view), falls back to original `listThreads` for single-connection efficiency.
- **mail-list.tsx:** Added colored dot indicator on thread rows when in unified multi-account view, with tooltip showing account email.
- **email-composer.tsx:** Enhanced "From:" picker to show all connected accounts with colored dots alongside aliases.

### Shared Auth (`packages/swift-auth`)

- **AuthService:** Added `linkSocialAccount(provider:)` method for linking additional OAuth accounts to an existing authenticated user via ASWebAuthenticationSession.
- **AuthError:** Added `notAuthenticated` and `networkError` cases.

## [2026-04-03] iOS — Multi-account connections service and inbox filtering

### iOS (`apps/ios/Todus`)

- **ConnectionsService:** New `@Observable` service (`Services/API/ConnectionsService.swift`) that fetches connected email accounts from the `connections.list` tRPC route, manages enabled/disabled filter state per account in UserDefaults, and exposes toggle/enableAll/setDefault/deleteConnection APIs.
- **AppServices:** Added `connectionsService` property so all views can access it via `@Environment(AppServices.self)`.
- **Settings — dynamic connections list:** The Connected Services section now shows a dynamic list of connected accounts from the backend (with colored circles, provider names, email addresses, and connection status) instead of the hardcoded Gmail row. Includes an "Add Account" button. Falls back to the legacy Gmail row when connections haven't loaded yet.
- **EmailInboxView — multi-account filter chips:** When 2+ accounts are connected, a horizontal chip bar appears below the folder quick-switch row. Each chip shows a colored dot and truncated email; tapping toggles that account's visibility. An "All" chip selects all accounts.

## [2026-04-03] macOS — Multi-account connections service and sidebar integration

### macOS (`apps/macos`)

- **ConnectionsService:** New `@Observable` service that fetches connected email accounts from the `connections.list` tRPC route, tracks enabled/disabled state per account in UserDefaults, and exposes toggle/enableAll/setDefault APIs.
- **MacAppServices:** Added `connectionsService` property so all views can access it via `@Environment`.
- **Sidebar accounts:** When multiple accounts are connected, the Email section shows per-account rows with colored dots and toggleable checkmarks. The sidebar footer shows a row of small colored avatar circles for quick multi-account switching.

## [2026-04-03] Performance — Summary-driven inbox and warmer caches

### Web (`apps/mail`)

- **Summary-driven inbox rows:** Mail list rows now render from `mail.listThreads` summary data instead of issuing `mail.get` for every visible row, removing the inbox N+1 fetch pattern that made folder loads feel slow.
- **Predictive thread warming:** The inbox now prefetches the selected thread, nearby threads, and hovered rows so opening a conversation is usually warm by the time the user clicks it.
- **Persisted cache no longer self-invalidates:** Restored inbox cache is kept available on startup instead of being immediately invalidated after hydration, which improves perceived speed after reloads and app restarts.
- **Visible background refresh state:** Cached-first mail, home, tasks, and calendar surfaces now show a subtle updating indicator while background revalidation is running so fast cached paints still communicate that fresher data is on the way.
- **App-start warmup:** Client providers now warm settings, folders, inbox, tasks, and today's calendar window during idle time after the active connection resolves.
- **Task cache patching:** Web task create/update/delete flows now patch cached task queries directly on the tasks page, home page, calendar page, and search page instead of relying on broad refetches.

### Native (`apps/ios`, `apps/macos`)

- **Cached refresh indicators across key surfaces:** iOS and macOS inbox, home, calendar, and tasks surfaces now show a compact `Updating` or `Syncing` badge when cached content is already visible and a background refresh is running.
- **No cached-content flicker on Home:** Native Home events and recent-email sections now keep their warmed content on screen during refresh instead of swapping back to a blocking loading card.
- **Shared-folder sync visibility:** Native task tabs now expose the background shared-folder sync state so task data can stay interactive while sync progress remains visible.

### Backend (`apps/server`)

- **Thread summaries from the local thread store:** `mail.listThreads` now returns richer summary rows for DB-backed folder browsing, including sender, subject, timestamps, label-derived flags, and cache timestamps.
- **Search summary hydration:** Provider-backed search results are hydrated with cached thread detail when summary fields are missing, so search results still render meaningful preview data without regressing the fast folder-browsing path.

### Verification

- `pnpm exec tsc --noEmit -p apps/mail/tsconfig.json | rg "mail-list|use-optimistic-actions|client-providers|query-provider|use-threads|task-cache|mail/search/page|mail/tasks/page|mail/home/page|mail/calendar/page"` [No matches]
- `pnpm exec tsc --noEmit -p apps/server/tsconfig.json | rg "lib/driver/types|routes/agent/index|routes/agent/db/index|trpc/routes/mail.ts"` [Still reports pre-existing errors in unrelated sections of `routes/agent/index.ts` and `routes/mail.ts`]

## [2026-04-03] Infra — Drizzle migration journal

- **`apps/server/src/db/migrations/meta/_journal.json`:** Added missing entries for `0044_pale_luminals` and `0045_meeting_retention_guardrails` so `drizzle-kit migrate` runs them before `0046_assistant_second_brain`.
- **Note:** If the database was updated with `db:push` (or similar) while `__drizzle_migrations` only tracked through `0040`, `pnpm db:migrate` can fail with `relation "mail0_group" already exists`. Fix by inserting the SHA-256 hashes for already-applied migration SQL files into `drizzle.__drizzle_migrations` (matching `created_at` from the journal), or by resetting the local Docker Postgres volume when data loss is acceptable.

## [2026-04-03] AI — Second-brain briefing, open loops, and prepared work

### Backend (`apps/server`)

- **Second-brain assistant domain:** Added a new `assistant` router that turns mail/meeting/task context into durable assistant state instead of one-off thread heuristics.
- **Open-loop ledger:** Added persisted assistant open loops for needs-reply, waiting-on, deadline-risk, meeting follow-up, decision-needed, draft-ready, and research-needed states.
- **Prepared actions:** Added persisted prepared actions for reply drafts, task creation, event creation, follow-ups, and research so the assistant can queue work for approval.
- **Structured memory:** Added people-memory and workstream-memory tables so the assistant can remember relationship context, recent communication, unresolved asks, and workstream status.
- **Briefing API:** Added `assistant.getBriefing`, `assistant.listOpenLoops`, `assistant.getThreadContext`, `assistant.getPersonContext`, `assistant.getWorkstreamContext`, `assistant.listPreparedActions`, `assistant.generateDraft`, `assistant.applyPreparedAction`, `assistant.snoozeOpenLoop`, `assistant.dismissOpenLoop`, `assistant.recordFeedback`, and `assistant.getChangeFeed`.
- **Compatibility:** Kept existing `mailAssistant.*` APIs intact while allowing the new thread/inbox surfaces to read from the broader assistant state.

### Web (`apps/mail`)

- **Home becomes a briefing surface:** Home now shows assistant priorities, Needs You, Waiting On, Prepared work, and recent changes before the generic dashboard sections.
- **Inbox becomes queue-oriented:** Mail assistant nudges now come from grouped open-loop queues instead of looser thread-only nudges.
- **Thread context upgraded:** The thread assistant card now uses `assistant.getThreadContext`, showing recommendation, waiting state, changed-since-last-open, related people context, linked work, and prepared actions.
- **Assistant settings expanded:** Settings now expose briefing-engine controls, Home briefing visibility, waiting-on tracking, people memory, batch approvals, workday hours, and excluded sender/topic patterns in addition to the existing summary/draft/auto-send controls.

### iOS (`apps/ios/Todus`)

- **Home briefing parity:** Home now conditionally loads and shows the assistant briefing sections when the briefing engine is enabled.
- **Thread context parity:** Email thread assistant surfaces now use the richer second-brain context shape with recommendation, people context, changed-since-last-open, and prepared-draft awareness.
- **Settings parity:** The AI settings page now exposes the second-brain operating model, including briefing controls, waiting-on tracking, people memory, batch approvals, workday timing, and noise filtering.

### macOS (`apps/macos`)

- **Home briefing parity:** macOS Home now respects the same briefing-engine gating and shows the same prepared-work framing as web/iOS.
- **Settings parity:** macOS settings now expose the new assistant operating model and workday/noise-filter controls.
- **Target graph stabilization:** Added `AppLogger.swift` back into the macOS Xcode target and fixed follow-on compile issues in meetings/tasks/assistant-panel paths discovered during the second-brain verification build.

### Verification

- `pnpm exec tsc -p apps/mail/tsconfig.json --noEmit` filtered to the changed assistant files produced no matches for [mail-display.tsx](/Users/ludvighedin/Programming/personal/mail/apps/mail/components/mail/mail-display.tsx), [mail.tsx](/Users/ludvighedin/Programming/personal/mail/apps/mail/components/mail/mail.tsx), [home/page.tsx](</Users/ludvighedin/Programming/personal/mail/apps/mail/app/(routes)/mail/home/page.tsx>), and [settings/general/page.tsx](</Users/ludvighedin/Programming/personal/mail/apps/mail/app/(routes)/settings/general/page.tsx>).
- `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator build CODE_SIGNING_ALLOWED=NO` [Passed]
- `xcodebuild -project apps/macos/TodusMac.xcodeproj -scheme TodusMac -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO` [Passed]

## [2026-04-03] UX — Connection CTA, localization, and task flow fixes

### iOS (`apps/ios/Todus`)

- **Attachment thumbnails:** Task attachment thumbnails now load off the main actor before updating the SwiftUI image state, preventing visible UI stalls while thumbnails are generated.
- **Task folder creation failure feedback:** Task detail sheet now surfaces a visible error when inline folder creation fails instead of silently doing nothing.

### macOS (`apps/macos`)

- **Assistant connection accuracy:** The assistant panel now treats email connectivity as `emailService.hasConnection` instead of inferring it from loaded threads, so connect prompts reflect the real auth state.
- **Email connect recovery:** The assistant panel’s `Connect Email` actions now open Internet Accounts in System Settings and fall back to a helpful alert if the deep link cannot be opened.
- **Service-specific CTA matching:** Assistant connection banners now only appear for explicit calendar/email disconnection phrases, avoiding false positives from generic “not connected” wording.
- **Tasks empty state action:** The macOS tasks empty state now always invokes a required create callback instead of silently no-oping.

### Web (`apps/mail`, `apps/web`)

- **Assistant email CTA matching:** The web AI compose chat now uses stricter email-connection phrase detection before showing the connect-email CTA.
- **Sidebar dialog accessibility:** The compose dialog now exposes descriptive screen-reader-only title and description text instead of empty Radix dialog labels.
- **Meetings auth redirect:** The meetings loader now constructs the login redirect with `URL` normalization so `VITE_PUBLIC_APP_URL` cannot produce double slashes.
- **Locale coverage:** Requested Catalan, German, Persian, French, Hindi, Japanese, Latvian, Dutch formatting, Polish, Portuguese, Russian, Turkish, Arabic, Hungarian, and Korean locale fixes were applied across `apps/mail/messages` and `apps/web/messages`.

## [2026-04-03] UX — Native onboarding and task clarity pass on iOS + macOS

### iOS (`apps/ios/Todus`)

- **Onboarding copy refresh:** Auth, Gmail, Reminders, and tab-bar onboarding now share one product promise, explain the benefit of each step more directly, and use lower-friction skip copy that tells users they can finish setup later in Settings.
- **Onboarding feedback states:** Gmail and Reminders onboarding now surface inline helper/error messaging so failed connection or denied-permission states are understandable instead of silent.
- **Tasks discoverability:** The Tasks page now exposes a local `Add Task` action in the header, removes the old standalone current-view chip, and uses labeled mode toggles instead of icon-only buttons.
- **Tasks clarity:** Non-list task modes now explicitly tell users that completed tasks stay in List, list empty-state copy points to the real creation path, and task-row metadata has a clearer hierarchy with due date/status emphasized over folder noise.
- **Board scrolling:** The board view now scrolls vertically and horizontally as separate axes instead of allowing free-form canvas panning.

### macOS (`apps/macos`)

- **Onboarding copy refresh:** Auth, Gmail, Calendar, and startup onboarding now use the same workspace framing as iOS, clearer outcome-based skip copy, and inline guidance that reduces setup anxiety.
- **Permission feedback:** Calendar onboarding now keeps the user on the step when access is denied and explains the Settings recovery path instead of silently advancing.
- **Startup preference polish:** Startup-view onboarding now presents Home as the recommended default and keeps the skip path aligned with that recommendation.
- **Tasks discoverability:** The Tasks page now includes a local `Add Task` action, labeled view toggles, a clearer completed-visibility note outside List, and stronger empty-state guidance.
- **Task editing parity:** macOS task detail editing now supports changing the task folder, and list/board rows communicate clickability more clearly with lighter metadata and a trailing chevron.

### Verification Details

- `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -configuration Debug -destination 'generic/platform=iOS' build` [Resolved]
- `xcodebuild -project apps/macos/TodusMac.xcodeproj -scheme TodusMac -configuration Debug build` [Blocking] existing unrelated compile failure in [EmailModels.swift](/Users/ludvighedin/Programming/personal/mail/apps/macos/TodusMac/Domain/EmailModels.swift) referencing missing `AppLogger`.

## [2026-04-03] Native App Readiness — Phase 3 Polish & Performance

### Both Platforms (iOS + macOS)

- **Fix: Request timeouts** — All `URLRequest` objects in `TodosAPIClient` now use a 30-second timeout (`timeoutInterval: 30`) to prevent indefinite hangs on bad connectivity.

### iOS (`apps/ios/Todus`)

- **Fix: AppConfiguration URL force unwraps** — Moved hardcoded URL strings to `static let` constants (constructed once, guaranteed valid). Eliminates repeated `URL(string:)!` force unwraps.
- **Fix: GroupChat adaptive polling** — Polling interval now adapts: 5s when the view is active, 30s when the app is backgrounded. Uses `scenePhase` to toggle `setActive()`. Reduces battery drain.

### macOS (`apps/macos/TodusMac`)

- **Feature: Structured logging** — Created `AppLogger.swift` (mirrors iOS). Replaced all 32 `print("[...")` calls across 9 files with `AppLogger.shared.log(...)` for persistent file-based logging and diagnostic sharing.
- **Feature: Email error state + retry** — Added dedicated `errorState` view to `MacEmailInboxView` with error message and "Try Again" button (matching the iOS pattern). Previously, failed loads showed the empty state.
- **Feature: Accessibility labels** — Added `accessibilityLabel` and `accessibilityHint` to toolbar buttons (Notifications, More Options, Create, Search) for VoiceOver support.

### Files changed

- `apps/ios/Todus/Todus/Data/AppConfiguration.swift`
- `apps/ios/Todus/Todus/Services/API/TodosAPIClient.swift`
- `apps/ios/Todus/Todus/Services/AI/GroupChatService.swift`
- `apps/ios/Todus/Todus/Features/AI/GroupChatView.swift`
- `apps/macos/TodusMac/Services/AppLogger.swift` (new)
- `apps/macos/TodusMac/Services/API/TodosAPIClient.swift`
- `apps/macos/TodusMac/Services/Email/EmailService.swift`
- `apps/macos/TodusMac/Services/Meetings/MeetingsService.swift`
- `apps/macos/TodusMac/MeetingsService.swift`
- `apps/macos/TodusMac/App/MacAppServices.swift`
- `apps/macos/TodusMac/App/MacRootView.swift`
- `apps/macos/TodusMac/Views/Tasks/MacTasksView.swift`
- `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`
- `apps/macos/TodusMac/Views/Create/MacCreateSheet.swift`
- `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`
- `apps/macos/TodusMac/Views/Email/MacEmailInboxView.swift`
- `apps/macos/TodusMac/Domain/EmailModels.swift`

---

## [2026-04-03] Native App Readiness — Critical Bug Fixes & UX Hardening

### Both Platforms (iOS + macOS)

- **Fix: Silent email mutation failures** — `markAsRead()`, `markAsUnread()`, `archiveThreads()`, `deleteThreads()`, and `toggleStar()` previously had empty `catch {}` blocks. User actions would silently fail with no feedback. All now set `errorMessage` (already rendered in views) and log the error.
- **Fix: Brittle session-expired detection** — Replaced string matching `error.errorDescription?.contains("Session expired")` with type-safe `catch APIError.unauthorized`. The API client already throws this enum case for all 401s.
- **Fix: Network vs server error messages** — `loadThreads()` now distinguishes `URLError` ("No internet connection") from server errors ("Failed to load emails. Please try again.") instead of showing a generic message.

### Shared Auth (`packages/swift-auth`)

- **Fix: Token refresh race condition** — Added `activeRefreshTask` coalescing gate in `refreshAccessToken()`. When multiple API calls receive 401 simultaneously, only one refresh network request fires; subsequent callers await the in-flight result instead of triggering duplicate requests.

### iOS (`apps/ios/Todus`)

- **Fix: Force cast crash in SupabaseEdgeFunctionClient** — Replaced `EmptyResponse() as! Response` with safe conditional cast (`as?`) + guard.
- **Fix: Force unwrap crashes in date computations** — `CalendarTaskView.recomputeBuckets()` and `HomeView.recomputeTasksDueToday()` used `Calendar.date(byAdding:)!`. Replaced with `guard let` + early return.
- **Fix: CalendarService force unwrap after nil check** — `scheduleFolderMapPruneIfNeeded()` used `lastFolderPruneAt!` after a nil check. Replaced with `if let` binding.

### macOS (`apps/macos/TodusMac`)

- **Fix: Settings session revocation errors hidden** — Added `settingsError` state + `.alert()` modifier so users see "Could not revoke session" instead of silent failure.
- **Feature: Offline network banner** — `MacRootView` now reads `networkMonitor.isConnected` and shows a red "No internet connection" capsule banner at the top of the app. Animated in/out with `.snappy`.

### Files changed

- `apps/ios/Todus/Todus/Services/Email/EmailService.swift`
- `apps/macos/TodusMac/Services/Email/EmailService.swift`
- `packages/swift-auth/Sources/TodusAuth/AuthService.swift`
- `apps/ios/Todus/Todus/Services/API/SupabaseEdgeFunctionClient.swift`
- `apps/ios/Todus/Todus/Features/Tasks/CalendarTaskView.swift`
- `apps/ios/Todus/Todus/Features/Home/HomeView.swift`
- `apps/ios/Todus/Todus/Services/Calendar/CalendarService.swift`
- `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`
- `apps/macos/TodusMac/App/MacRootView.swift`

---

## [2026-04-03] AI Chat — Service Connection UX + iOS Input Hang Fix

### iOS (`apps/ios/Todus`)

- **Fix: Input-tap hang** — Capped `mentionOptions` thread iteration at 50 entries before dictionary grouping, preventing O(n) main-thread freeze when tapping the AI chat input field.
- **Service connection messaging** — Updated system prompt: AI now says "Calendar/Email is not connected" instead of "access disabled by user". AI is told to direct users to connect in settings.
- **Suggestion filtering** — Calendar tab returns no suggestions (shows connect CTA instead) when EventKit permission is not granted. Email tab does the same when inbox is not loaded.
- **Connect CTA in messages** — `MessageBubble` detects when a service is mentioned in an AI response while that service is disconnected, and shows a compact "Connect Calendar / Email" pill button inline.
- **Connect CTA in empty state** — When the active tab's suggestion pool is empty, a `connectServicesPrompt` shows compact capsule buttons to request calendar access or navigate to email.

### macOS (`apps/macos/TodusMac`)

- **Service connection messaging** — Same system prompt update as iOS. AI says "not connected" for calendar/email when not available.
- **Suggestion filtering** — Calendar and email sections return empty pools when respective services aren't connected; connect prompt shown instead.
- **Connect CTA in messages** — `MacMessageBubble` shows connect banner when AI mentions a disconnected service.

### Web (`apps/mail`)

- **Markdown rendering** — Fixed `markdownStyles` to give headings visual hierarchy (bold/semibold weight), proper paragraph/list sizing, `outside` list-item positioning, styled code blocks, and blockquote styling. Added `normalizeMarkdown()` to convert single `\n` to `\n\n` so CommonMark sees paragraph breaks.
- **Suggestion filtering** — `ExampleQueries` hides all email suggestions when no email connection exists and shows a "Connect Email Account" link instead.
- **Connect CTA in messages** — Inline `<a>` to `/settings/connections` shown below assistant messages that mention "email", "inbox", or "not connected" when no email account is linked.
- **Chat entitlement gating** — `isChatEnabled` now blocks chat until billing has finished loading and the feature is confirmed enabled, so users do not get access before entitlement is known.

### Files changed

- `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`
- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`
- `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`
- `apps/macos/TodusMac/Services/AI/MacAIChatService.swift`
- `apps/mail/components/create/ai-chat.tsx`

---

## [2026-04-03] UX — iOS email thread view polish pass

### iOS (`apps/ios/Todus`)

- **Tab bar hidden in thread view:** Added `hideTabBar` flag to AppServices so the custom floating tab bar hides when viewing an email thread. Reply buttons are now fully visible.
- **Header redesign:** Removed solid background, replaced with transparent-to-scrim gradient. Action icons (mark unread, archive, delete) grouped in a single glass capsule. Back button and Ask AI button are standalone circles.
- **Ask AI in header:** Added sparkles button with the same gradient as the tab bar AI icon. Opens the AI chat sheet with thread context attached.
- **Bottom reply bar:** Removed solid background/blur. Reply/Reply all/Forward buttons now float freely with a subtle scrim gradient that fades content out behind them.
- **Scroll-aware title:** Subject appears centered in the header at body text size (15pt medium) when scrolled past the subject row.
- **Summary card trimmed:** AI summary capped at 3 lines, action items at 3 bullets max. Keeps the card compact and scannable.
- **Contextual action buttons:** Buttons now only appear when relevant — Extract task (when AI found tasks), Draft reply (when reply needed), Book follow-up (when follow-up flagged), Create event (when meeting detected). No more irrelevant buttons.
- **Action buttons unclipped:** Moved padding inside the ScrollView HStack so right-side pills are no longer clipped by parent padding.

### Files changed

- `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift` — Full rewrite
- `apps/ios/Todus/Todus/App/AppServices.swift` — Added `hideTabBar` property
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift` — Conditionally hide custom tab bar

## [2026-04-03] UX — Native home, tasks, and email usability pass on iOS + macOS

### iOS (`apps/ios/Todus`)

- **Home:** The Home dashboard now distinguishes loading from empty states for events and email, surfaces a compact partial-setup card when Gmail or Calendar still needs connection, adds explicit section actions (`Open` / `View all`), and visually demotes `Other Spaces` so today-focused content reads first.
- **Tasks:** Task search and sort now apply consistently across List, Board, Table, and `By Date`; the mode helper text explains what each layout is for; Board and Table explicitly hide completed work outside List; board columns now have clearer empty states; and due dates are more visually prominent inside board cards.
- **Email:** The inbox now shows a persistent mailbox cue with quick-switch chips for primary folders, clarifies search state (`Filtering loaded...` vs `Searching...`), compresses assistant nudges, and keeps the thread list primary. Thread detail now shows a short message preview before AI summary/actions and consolidates the main thread actions into one top cluster.
- **Verification:** `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' build` succeeds after the UX pass.

### macOS (`apps/macos`)

- **Home:** Added distinct loading cards for events/tasks/email, a compact partial-setup banner when Gmail or Calendar is still disconnected, and actionable empty states with direct next-step buttons for Calendar, Tasks, and Inbox.
- **Tasks:** The toolbar now shows the active sort label alongside the sort icon, explains the purpose of the current view mode more clearly, adds a visible note when completed tasks stay in List, and upgrades the empty state with an explicit create/clear-search action.
- **Email:** The inbox now shows the current mailbox context inside the pane, de-emphasizes assistant nudges relative to the thread list, clarifies search status, improves the empty detail guidance, and moves the AI card below a short message preview in thread detail so reading comes first.
- **Verification:** `xcodebuild -project apps/macos/TodusMac.xcodeproj -scheme TodusMac -destination 'platform=macOS' build` succeeds after the UX pass.

## [2026-04-03] Fix — Native email mailbox clarity and responsiveness pass

### iOS (`apps/ios/Todus`)

- **Connection-state gating:** The inbox now distinguishes `checking connection` from `not connected`, so the Gmail connect surface no longer flashes before the initial connection check completes.
- **Folder-specific empty states:** Empty mailboxes now use folder-aware copy such as `No drafts`, `Nothing sent yet`, and `Trash is empty`, each with a short explanation of what belongs there.
- **Verification:** `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` succeeds after the inbox-state changes.

### macOS (`apps/macos`)

- **Instant folder switching:** The macOS email service now hydrates each mailbox from an in-memory per-folder cache before refreshing, so switching between Inbox, Drafts, Sent, and the secondary folders no longer waits on a cold reload.
- **Connection-state gating:** The macOS email page now shows a loading state while checking Gmail connectivity instead of briefly rendering the connect prompt during startup.
- **Sender avatars:** The inbox list and thread detail now use the same avatar-resolution pipeline as iOS, preferring contact/domain imagery before falling back to deterministic initials.
- **Folder-specific empty states:** Empty mailbox messaging is now specific to the selected folder instead of the generic `No emails` copy.
- **Verification:** The changed email files compile during the macOS build, but the full target still fails because of pre-existing unrelated errors in `apps/macos/TodusMac/Views/Tasks/MacTasksView.swift`.

## [2026-04-03] Fix — iOS startup/runtime hang mitigation and tracing pass

### iOS (`apps/ios/Todus`)

- **Calendar hot path:** `CalendarService` no longer prunes folder mappings on every event fetch. Pruning is now throttled, bounded to a one-year window, and instrumented with signposts. Added a short-lived today-events cache to avoid repeated EventKit work when returning to Home.
- **Startup/task/email tracing:** Added new `OSSignpost` intervals for calendar fetches, folder-map pruning, shared-folder sync, email connection checks, task-list recomputes, and attachment decoding. Added a debug-only main-thread hang watchdog that logs stalls over 200 ms.
- **Startup/runtime throttling:** `TaskCaptureService.syncSharedFolders`, `EmailService.checkConnection`, and shared AI profile loading are now coalesced/throttled to avoid repeated work when switching tabs or reopening surfaces. `MainTabView` no longer force-rebuilds active tabs with `.id(selectedTab)`.
- **Task-view churn:** Reduced broad observation in the tasks shell by passing narrower dependencies into `InboxView`, `BoardView`, `BoardColumnView`, and `TaskTableView`. Removed the old board string-signature regrouping path and replaced task recompute paths with signposted digest-based updates.
- **Attachment I/O:** Replaced synchronous security-scoped file imports in Create, Task Detail, and AI Chat with async imports. Added thumbnail downsampling/caching in `AttachmentService` and switched attachment previews to lazy thumbnail loading instead of repeated full image decodes during view rendering.
- **Verification:** `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` now succeeds after the performance changes.

## [2026-04-03] UX — Native iOS/macOS clarity pass with small, high-impact copy and guidance updates

- **iOS onboarding (`RootView.swift`, `GmailOnboardingView.swift`, `RemindersSetupView.swift`, `TabBarOnboardingView.swift`):** Added a compact onboarding progress pill across the Gmail, Reminders, and tab-bar setup steps. Tightened the onboarding benefit copy and renamed the tab-bar customization buckets to `Pinned tabs` and `Available tabs`, plus added a clearer preview helper line.
- **iOS shell (`MainTabView.swift`):** Added a one-time, non-blocking coachmark overlay for the floating tab bar so first-time users get quick context for `More spaces`, `Ask AI`, and `Create` without adding permanent tab labels.
- **iOS tasks/email/home/create (`TasksTabView.swift`, `EmailInboxView.swift`, `HomeView.swift`, `CreateSheet.swift`):** Added current-mode and active-sort clarity in Tasks, a first-use folder-switch hint in Email, renamed Home's overflow section to `Other Spaces` with clearer helper text, and refined the Create overlay with simpler placeholder/helper copy plus lighter visual emphasis on advanced metadata controls.
- **macOS shell/auth/search/brief (`MacRootView.swift`, `MacAuthView.swift`, `MacSearchView.swift`, `MacNotificationCenterView.swift`):** Reframed the bell surface as a `Daily Brief`, tightened auth/restoring reassurance copy, clarified search intent, and subtly increased toolbar emphasis for create/search while slightly de-emphasizing secondary controls.

## [2026-04-03] Fix — Native transcribe buttons: idempotent teardown on iOS + macOS

- **iOS (`VoiceInputButton.swift`, `AIChatView.swift`):** Made speech-recorder teardown idempotent so repeated stop/final/error callbacks can no longer double-remove audio taps or double-deliver transcripts. Added tap-tracking, guarded re-entry, and safer finalization for both the shared voice button and the AI chat transcribe button.
- **macOS (`MacAssistantPanel.swift`):** Applied the same stop/finalization hardening to the macOS speech input controller so the assistant transcribe button no longer races engine shutdown against recognizer callbacks.
- This specifically targets the freeze/close-on-press behavior reported around the transcribe button by preventing invalid audio-engine lifecycle transitions while the Speech framework is still unwinding.

## [2026-04-03] Feat — iOS tab bar: burger menu, tighter layout, Home More section + Docs

### iOS (`apps/ios/Todus`)

- **CustomTabBar.swift**: Burger `line.3.horizontal` button now first in the nav pill (replaces ellipsis in action pill). Removed ellipsis from action pill — right pill is now just AI + create. Narrowed all button frames (62→50px nav, 54→50px action). Reduced pill padding and HStack spacing for a tighter look.
- **AppTab.swift**: `defaultNavTabs` remains `[home, tasks, email, calendar]`; the burger sits outside the configured tabs and keeps the visible pill from feeling cramped.
- **AppServices.swift**: `tabBarTabs` decode still clamps invalid values, but the configured tab set remains capped at 4.
- **MoreSheetView.swift**: Added Meetings and Calendar (when not in tab bar) as NavigationLinks. Added "Customize Tab Bar" shortcut. Now uses `@Environment(AppServices.self)` to conditionally show items.
- **HomeView.swift**: Refactored `moreSection` — tapping nav cards opens a sheet (meetings) or navigates the tab (calendar). Added permanent Docs card (always visible, opens as a sheet). Replaced "Open" button pill with a chevron for a standard iOS row feel.
- **TabBarCustomizationView.swift**: Kept the customization UI aligned with the 4-tab cap and the burger slot.
- **TabBarOnboardingView.swift**: Kept the onboarding preview aligned with the 4-tab cap and the burger slot.

## [2026-04-03] Fix — Notifications: iOS parse error + macOS bell button

- **Backend fix:** `/api/ai/chat` was hardcoding `stream: true`, ignoring the `stream: false` sent by `NotificationDigestService`. Added `shouldStream` flag that respects the request param. Non-streaming requests now return the raw OpenAI completion JSON directly — fixing the iOS "couldn't be read because it isn't in the correct format" error.
- **macOS notifications bell:** Re-added the notifications toolbar button (previously removed as placeholder). Added `MacNotificationCenterView` — a macOS-native AI-powered digest sheet with the same logic as the iOS counterpart but adapted for `MacAppServices`. Uses a popover off the bell button.
- **macOS `TodosAPIClient`:** Made `baseURL` internal (was `private`) so `MacNotificationCenterView` can build the request URL.

**Files:** `apps/server/src/routes/ai.ts`, `apps/macos/TodusMac/Views/Notifications/MacNotificationCenterView.swift`, `apps/macos/TodusMac/App/MacRootView.swift`, `apps/macos/TodusMac/Services/API/TodosAPIClient.swift`, `apps/macos/TodusMac.xcodeproj/project.pbxproj`

## [2026-04-03] Fix — AI chat markdown formatting and line breaks (iOS + macOS)

- **Instant markdown rendering (iOS + macOS):** AI responses now render headings (`#`), bullets (`-`), bold, and code blocks _during streaming_ instead of showing raw markdown characters. Removed the two-phase `showFullMarkdown` toggle — `fullMarkdownText` (`.full` AttributedString syntax) is used from the first token. Typewriter animation is preserved; the blinking cursor overlay continues during streaming.
- **macOS multiline input:** Replaced SwiftUI `TextField` + `onSubmit` with a custom `NSViewRepresentable` (`MacChatTextInput`) wrapping `NSTextView`. Return now inserts a line break; **Cmd+Return** sends the message. The send button tooltip updated to `⌘↵`.
- **User bubble line breaks (iOS + macOS):** Added `.fixedSize(horizontal: false, vertical: true)` to `Text(message.content)` in user bubbles to guarantee vertical expansion for multi-line messages.
- Added `MacBlinkingCursor` component on macOS to show a blinking cursor during AI streaming.

**Files:** `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`, `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`

## [2026-04-03] Fix — iOS email inbox: scrollable nudges + unread dot indicator

- **Assistant nudges moved inside the List:** No longer a fixed header blocking ~40% of the screen. Now scrollable List rows at the top of the thread list — users see emails immediately and scroll nudges away naturally.
- **Unread indicator:** 3×40pt accent bar → 7pt circle dot with 18pt fixed-width cell for column alignment. Matches macOS app pattern.
- **Row padding:** `EmailRowView` uses symmetric `padding(.horizontal, 16)` now that it owns its own insets.

**Files:** `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`, `apps/ios/Todus/Todus/Features/Email/EmailRowView.swift`

## [2026-04-03] Fix — macOS email thread: scroll passthrough + smarter AI assistant card

- **Scroll fix:** Subclassed WKWebView as `PassthroughWKWebView` — overrides `scrollWheel(with:)` to forward events to `nextResponder` instead of consuming them. The outer SwiftUI `ScrollView` now scrolls the full thread no matter where the cursor is.
- **Assistant card redesign:** Removed raw "20% confidence" and "High risk" pills (technical internals, confusing to users). Card leads with plain-language actionable suggestions derived from `replyNeeded`, `meetingRequested`, `followUpNeeded`, `suggestedTasks` flags. `actionItems: [String]` rendered as a bullet list. Uncertainty note only shown when confidence < 40%. Buttons have `.help()` tooltips explaining disabled states. Loading skeleton while data fetches.

**Files:** `apps/macos/TodusMac/Views/Email/MacEmailThreadView.swift`

## [2026-04-03] Fix — macOS email thread UX: inline split panel, scrolling, design cleanup

- **Split-panel layout (macOS):** Email threads now open inline in a right-side detail pane instead of a modal sheet. Thread list (300px fixed) sits left, selected thread fills the right. Matches web app behavior.
- **Scrolling fixed:** `EmailHTMLView` (WKWebView) now measures its full content height via JS `scrollHeight` after page load and reports it via a `@Binding<CGFloat>`. The outer SwiftUI `ScrollView` handles all scrolling — no more tiny inner-scroll window.
- **Design cleanup:** Removed card background/border boxing from individual messages; messages flow with thin dividers. Removed per-message action buttons (redundant with assistant card). Simplified assistant card — removed nested inner summary card, flatter layout.
- **`onClose` param on `MacEmailThreadView`:** Inline mode calls `onClose()` to deselect; sheet mode (from search) continues to use `dismiss()`.

**Files:** `apps/macos/TodusMac/Views/Email/MacEmailInboxView.swift`, `apps/macos/TodusMac/Views/Email/MacEmailThreadView.swift`, `apps/macos/TodusMac/App/MacRootView.swift`

## [2026-04-03] Fix — iOS/macOS transcribe freeze, AI chat input layout redesign

- **Transcribe freeze fix (iOS + macOS):** Moved ALL heavy audio operations (AVAudioSession.setActive, AVAudioEngine.inputNode, engine.prepare(), engine.start()) off the main thread using `@unchecked Sendable` holder classes + `Task.detached`. Previously only `setActive` was off-main; `inputNode` access and `engine.start()` still blocked for several seconds during hardware init.
- Three separate implementations fixed: `ChatVoiceInputButton.VoiceRecorder` (AIChatView.swift), `VoiceController` via new `AudioEngineHolder` (VoiceInputButton.swift), `MacVoiceController` via new `MacAudioEngineHolder` (MacAssistantPanel.swift).
- Redesigned AI chat input to two-row layout: full-width text field on top, button row below. Fixes text being pushed right and not full-width.
- Fixed 9+ second input freeze caused by GeometryReader layout cycle in the old single-row HStack.
- Full-screen expand button only shown when text reaches max height (≥118pt), with consistent 30×30 sizing.
- Fixed multiline input sliding below keyboard in empty state: moved `inputSection` into `.safeAreaInset(edge: .bottom)` — same pattern as `conversationView` — so the input bottom is always pinned just above the keyboard regardless of how many lines are typed.

**Files:** `apps/ios/Todus/Todus/Features/Voice/VoiceInputButton.swift`, `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`, `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`

## [2026-04-03] Fix — AI chat persistence and input blocking

### Web (`apps/mail`)

- **layout.tsx**: Moved `AISidebar` and `AIToggleButton` from `mail.tsx` into the shared mail layout so the chat persists on all pages (home, tasks, meetings, etc.).
- **ai-sidebar.tsx**: Replaced `ResizablePanel`-based sidebar with a `fixed` right panel (`fixed top-2 right-1 bottom-1 z-40 w-[360px]`) so sidebar mode works everywhere without needing a `ResizablePanelGroup`. Added self-gating `if (!activeConnection?.id) return null` inside the component.
- **ai-chat.tsx**: Fixed paywall overlay (`absolute inset-0`) covering the text input by adding `relative` to the scroll container, scoping the overlay to only the messages area. Fixed billing loading race condition: `isChatEnabled = !isBillingLoading && chatMessages.enabled` so users stay blocked until billing is loaded and entitlement is confirmed.
- **mail.tsx**: Removed `AISidebar` and `AIToggleButton` (now rendered globally in layout).

## [2026-04-03] Fix — meeting retention and scheduling guardrails

### Server (`apps/server`)

- **Migration 0045** (`apps/server/src/db/migrations/0045_meeting_retention_guardrails.sql`): Adds `last_pruned_at`, enforces unique `recall_bot_id`, and includes the duplicate-check guard before the constraint lands.
- **meeting-retention.ts**: Added staleness-aware pruning that writes `last_pruned_at`, returns a uniform `{ deleted }` shape, and stops scanning on every read.
- **trpc/routes/meet.ts**: Hardened Recall bot scheduling with an atomic claim before the external API call so concurrent syncs do not double-schedule the same meeting.
- **routes/recall-webhook.ts**: Moved retention cleanup out of the summary error path and fixed the summary sentinel rollback to use the in-scope claim flag.
- **db/schema.ts**: Matches the migration by adding the `last_pruned_at` integration column and making `recall_bot_id` unique.

### iOS (`apps/ios/Todus`)

- **AppServices.swift**: Tab bar restore now falls back to the default 4-tab layout when decoded persisted tabs are invalid or insufficient.
- **EmailService.swift**: Cached inbox data now checks staleness and refreshes in the background instead of leaving the timestamp fields unused.
- **TabBarCustomizationView.swift**: Fixed the delete handler to pass an `IndexSet` to `remove(atOffsets:)`.

## [2026-04-03] Feat — iOS tab bar customization + meetings UX overhaul

### iOS (`apps/ios/Todus`)

- **MeetingsListView.swift**: Fixed title position via `AppTopHeader` pattern; pull-to-refresh replaces toolbar sync button.
- **AppTab.swift**: Added `description`, `isRequired`, `defaultNavTabs`; conforms to `Codable`.
- **AppServices.swift**: Added `tabBarTabs` (persisted, default 4 tabs), `hasConfiguredTabBarPrompt`, `navigateToSheet`.
- **CustomTabBar.swift**: Accepts `tabs: [AppTab]` — renders user-configured tabs (max 4).
- **MainTabView.swift**: Passes `tabBarTabs`; presents non-tab pages as sheets via `navigateToSheet`.
- **TabBarCustomizationView.swift** (new): Drag-reorder + add/remove tabs in Settings.
- **TabBarOnboardingView.swift** (new): One-time onboarding step for tab bar customization.
- **RootView.swift**: Added tab bar onboarding step in sequence.
- **SettingsView.swift**: Added "Navigation → Tab Bar" section.
- **HomeView.swift**: "More" section surfaces non-tab pages with description + "Open" sheet button.

## [2026-04-03] Fix — macOS Dock icon crop

### macOS (`apps/macos`)

- **TodusMac/Resources/Assets.xcassets/AppIcon.appiconset**: Regenerated the macOS app icon set from the iOS 1024 px master artwork so the Dock icon uses the same padding and no longer appears cropped.
- **apps/ios/Todus/status_macos.md**: Added a build note documenting the icon asset correction.

## [2026-04-03] Fix — Cloudflare web build cleanup

### Web (`apps/mail`)

- **apps/mail/app/(routes)/mail/docs/[docId]/page.tsx**: Fixed the doc editor import to use the default `Editor` export from `@/components/create/editor`, resolving the Rollup/Vite missing export build error.
- **apps/mail/components/mail/note-panel.tsx**: Replaced `window.confirm` with the existing shadcn dialog pattern for note deletion so the code passes the `no-alert` lint rule without suppressions.
- **apps/mail/app/(auth)/todus/login/page.tsx** and **apps/mail/app/(auth)/todus/signup/page.tsx**: Removed dead `false && (...)` JSX branches and the now-unused auth form code so Oxlint no longer flags constant boolean conditions.

## [2026-04-03] Fix — Native meetings follow-up regressions

### Native meetings (`apps/ios`, `apps/macos`)

- **MeetingDetailView.swift / MacMeetingDetailView.swift**: Detail refreshes after `generateSummary` and `scheduleBot` now preserve the current content instead of blanking the whole screen behind a full-screen loading spinner.
- **iOS MeetingsService.swift**: Calendar sync and bot scheduling now reload meetings with the current search/status filters preserved, so the visible list stays consistent with the active search field.
- **MacMeetingsView.swift**: Reordered grouped meeting sections to `Today → This Week → Upcoming → Earlier`, matching iOS and prioritizing the most time-sensitive meetings first.
- **iOS MeetingsListView.swift**: Removed the stale top-level duplicate and kept the active `Meetings/MeetingsListView.swift` implementation, which uses the same `Starting` label as the detail view for `bot_joining`.

## [2026-04-03] Enhancement — Production-grade auth with access + refresh tokens

Implemented a proper access + refresh token pattern for native apps, matching production apps like Gmail, Slack, and Twitter. Users feel "always signed in" — security is enforced behind the scenes, not by annoying logouts.

### Architecture

- **Access token (JWT)**: 15-minute expiry, used for all API calls. Stateless JWKS verification, no DB lookup.
- **Refresh token (session token)**: 90-day sliding window, stored in Keychain. Used only to obtain fresh JWTs via `/auth/refresh-native-token`. Window extends daily on use via Better Auth's `updateAge`.
- **User experience**: App opens → JWT expired → refresh token exchanges for new JWT → user never notices. Only re-login if inactive 90+ days.

### Server (`apps/server`)

- **auth.ts**: JWT expiration set to 15 minutes (access token). Session `expiresIn` set to 90 days. `updateAge` set to 1 day for daily session extension. `cookieCache.maxAge` set to 90 days.
- **main.ts**: `/auth/mobile-token` now returns both a JWT (access) and raw session token (refresh) in the deep link. New `POST /auth/refresh-native-token` endpoint exchanges a refresh token for a fresh JWT, going through Better Auth's full session pipeline (validates session, extends expiresAt, mints JWT).

### Shared Auth (`packages/swift-auth`)

- **AuthService.swift**: Dual token storage (`bearerToken` for JWT, `refreshToken` for session token). Added `refreshAccessToken()` for transparent JWT refresh. Added `isJWTExpiredOrExpiring()` for proactive refresh. Updated `restorePersistedSession()` to refresh JWT on app launch. Updated `attemptSilentRefresh()` to use refresh pattern with legacy fallback. Updated `completeAuthentication()` to detect JWT vs session token and exchange accordingly for Apple/Email OTP flows. Updated `handleAuthCallback()` to extract refresh token from deep links. Improved all user-facing error messages.

### Native Apps (`apps/ios`, `apps/macos`)

- **TodosAPIClient.swift** (both platforms): Improved session expired error message.

### Session Revocation

Better Auth provides `/revoke-session`, `/revoke-sessions`, and `/revoke-other-sessions` endpoints. When a session is revoked, the refresh token becomes immediately invalid. The JWT remains valid for up to 15 minutes (standard JWT trade-off). No additional wiring needed.

### Future Improvements (documented, not implemented)

- Device trust / "remember me" (trusted devices get longer refresh window)
- Suspicious IP/device fingerprint detection for forced re-login
- JWT ID (`jti`) blacklisting for instant revocation
- Proactive token refresh in API clients (before 401, not after)

## [2026-04-02] Fix — Native app session expiration after inactivity

Root cause: Better Auth's `jwt()` plugin defaults to **15-minute expiration**. JWTs minted by `/auth/mobile-token` expired almost immediately, causing native app sign-outs.

### Additional fixes

- **MacAppServices.swift**: Shared folder sync now propagates local fetch failures instead of silently falling back to an empty folder list.
- **nav-main.tsx**: `NavItemExpandable` now receives `isUrlActive` explicitly, fixing a runtime reference error in expandable navigation items.
- **schemas.ts**: `mergeUserSettings` now keeps `categories` typed as full `MailCategory[]` while still allowing nested partial updates elsewhere.
- **MacMeetingsView.swift**: Sync icon rotation now initializes correctly when the meetings view appears during an in-flight sync.

## [2026-04-01] Feat — iOS More sheet + Docs WebView (apps/ios)

Added "More" overflow button (ellipsis) to the custom tab bar that opens a sheet containing a Docs WebView:

- `Features/Docs/DocsWebView.swift` — WKWebView wrapper loading `https://app.todus.app/mail/docs`; injects Bearer token on initial load; mirrors device colour scheme via JS at document start.
- `Features/Docs/MoreSheetView.swift` — sheet with NavigationStack + List; single "Docs" row with `NavigationLink` to `DocsWebView`; Done button in toolbar.
- `Features/Tasks/CustomTabBar.swift` — added optional `onMore: (() -> Void)?` property; added ellipsis button (44×46pt, `secondaryLabel` colour) after the + button in the action pill.
- `Navigation/MainTabView.swift` — added `@State private var showMoreSheet`, passes `onMore: { showMoreSheet = true }` to `CustomTabBar`, presents `MoreSheetView` as a `.sheet`.

## [2026-04-01] Feat — Doc editor page with auto-save (apps/mail/app/(routes)/mail/docs/[docId]/page.tsx)

Replaced the stub at `/mail/docs/:docId` with a full editor page:

- Two-column `ResizablePanelGroup` matching the docs list page layout; left panel hosts `DocTree` with the current doc highlighted via `selectedDocId`.
- Title: plain `<input>` (`text-2xl font-semibold`, no border) — saves on blur or Enter via `trpc.docs.update`.
- Editor: `<Editor>` (Tiptap/Novel); captures the live editor instance via `onEditorReady` so `getJSON()` / `getText()` provide JSONContent + plaintext for storage (since `onChange` emits HTML only).
- Content auto-save: inline debounce (1 s), calls `trpc.docs.update({ id, content, contentText })`.
- Loading state: shimmer bars (Tailwind `animate-pulse`); error/not-found state: message + Back link.
- Title seeded from server via `useEffect` (TanStack Query v5 — no `onSuccess` on `useQuery`).

## [2026-04-01] Feat — DocTree component + Docs list page (apps/mail/components/docs/doc-tree.tsx, apps/mail/app/(routes)/mail/docs/page.tsx)

Added `DocTree` sidebar component and replaced the `DocsPage` stub with a real two-column layout:

- `DocTree` — fetches workspaces via `trpc.docs.workspaces.list`, fetches root docs per workspace via `trpc.docs.list`, renders collapsible workspace sections with inline "new page" (+ icon) and "new workspace" buttons; loading skeletons; empty state.
- `DocsPage` — `ResizablePanelGroup` layout: left panel (20% default, 15% min) hosts `DocTree`; right panel shows an empty-state with "Select a page to start reading" + "New page" button; auth-guarded via `clientLoader`.

## [2026-04-01] Feat — Add docWorkspace + doc DB schema tables (apps/server/src/db/schema.ts)

Added two new Drizzle ORM tables for the Docs feature:

- `mail0_doc_workspace` — user-owned workspace container with optional emoji, createdAt/updatedAt
- `mail0_doc` — Notion-style page with self-referential parentId for nesting, Tiptap JSONContent storage, plaintext search mirror, cross-entity link columns, and three indexes
  Added `import type { AnyPgColumn }` to satisfy TypeScript's circular reference check on the self-referential FK.
  Migration NOT applied — run `pnpm db:generate && pnpm db:migrate` to apply.

## [2026-04-01] Fix — Code quality and bug fixes across all platforms

Batch of ~50 fixes across iOS, macOS, web, and server layers covering security, stability, and UX.

### Server (`apps/server`)

- **env.ts**: Made `RECALL_WEBHOOK_SECRET` optional (`?`)
- **recall.ts**: Wrapped `JSON.parse` in try-catch for cleaner parse error messages
- **recall-webhook.ts**: Implemented full HMAC-SHA256 signature verification with production warning when secret is not set; made media and transcript inserts idempotent via `onConflictDoUpdate`/`onConflictDoNothing`; transcript event only sets status to `ready` when transcript fetch succeeds; handles null `recallSegmentId` segments separately to avoid dedup failures on retry; read body once to avoid double-consume
- **schema.ts**: Added `.unique()` to `recallMediaId` and `recallSegmentId` columns
- **Migration 0043**: Adds unique constraints for `recall_media_id` and `recall_segment_id`
- **meet.ts**: LIKE wildcard escaping for search; `scheduleBot` cleans up orphaned bot on DB failure; `deleteMeeting` checks for active bot before deleting; Invalid Date guard in `syncFromCalendar`; N+1 eliminated in `syncFromCalendar` — batch-fetch all existing meetings via `inArray` before the loop
- **mail-assistant.ts**: Added TODO comment for hardcoded UTC timezone

### Security

- **Severity: critical** — Fixed a SQL injection vulnerability in `searchMeetingTranscriptTool` in `apps/server/src/routes/agent/tools.ts`. The vulnerable transcript search path now escapes LIKE wildcards before building the query, preventing potential arbitrary query modification and transcript data exfiltration from attacker-controlled search input. Affected released versions: all released builds containing the original meetings transcript tool before the 2026-04-01 fix. Immediate upgrade required: **yes**.

### Fixes

- **tools.ts (agent)**: Fixed meeting tools type to avoid `undefined` in `ToolSet`

### iOS (`apps/ios`)

- **GroupChatView.swift**: URL-encodes invite token; surfaces `joinGroup`/`leaveGroup` errors via alerts; only clears token on success
- **ShareConversationSheet.swift**: Added `@MainActor` to `createLink()`; removed redundant `MainActor.run {}`
- **SharedConversationView.swift**: `unlock()` only sets `wrongPassword = true` for auth failures (401/403/password errors)
- **EmailThreadView.swift**: `handleDraftReply` only sets `assistantDraftSeed` when `result.created == true`; `AssistantPill` uses `Color(.systemBackground)` for dark mode
- **AIChatView.swift**: Share sheet uses `.sheet(item:)` with `ShareConversationID` to prevent blank sheet
- **SettingsView.swift**: Auto-send toggle shows confirmation dialog before enabling
- **MeetingDetailView.swift**: Added error alerts for `generateSummary`/`scheduleBot`; stable `@State AVPlayer`
- **MeetingsListView.swift**: Added error state with retry button
- **MeetingsService.swift**: Added `loadError` property; removed `private` from `GenerateSummaryResponse`

### macOS (`apps/macos`)

- **MailAssistantModels.swift**: Added `Sendable` to `MailAssistantSettingsResponse`/`Settings`; stable stored `id` for `MailAssistantNudge`
- **GroupChatService.swift**: Replaced all `apiClient!` force-unwraps with guard-let; `createGroup` matches by returned id; per-iteration `guard let self` in polling loop
- **ShareConversationService.swift**: Replaced all `apiClient!` force-unwraps with guard-let
- **MacEmailInboxView.swift**: Disabled nudge button when `threadIds.isEmpty`
- **MacEmailThreadView.swift**: `onDismiss` clears `assistantDraftSeed`; `handleDraftReply` only shows notice when draft NOT created; renamed "Extract tasks" → "Extract task"
- **CalendarService.swift**: `pruneFolderMap` guards against calendar permission revocation
- **MacAssistantPanel.swift**: Closes share panel when `currentConversationID` becomes nil
- **MacMeetingDetailView.swift**: Added error alerts; stable `@State AVPlayer`; `scheduleBot` returns Bool for error detection
- **MacMeetingsView.swift**: Added "Upcoming" category for future meetings beyond this week; added error state when `loadError` is set and list is empty (with Retry button)
- **MeetingsService.swift**: Added `loadError`; removed `private` from `GenerateSummaryResponse`

### Web (`apps/mail`)

- **mail-display.tsx**: Refresh button handler wrapped in try-catch with `toast.error`
- **chat/page.tsx**: Added `onError` handler to `saveConversation`; `handleDeleteConversation` moves `handleNewChat()` to `onSuccess`
- **search/page.tsx**: Safe date parsing with `isValid()` for thread and task dates
- **tasks/page.tsx**: Added `aria-label` to search and quick-add inputs; `quickAddValue` cleared only on mutation success; removed stale `setDetailTask` spread
- **settings/general/page.tsx**: Replaced `as never` TypeScript cast with `as any` + eslint-disable comment
- **calendar/page.tsx**: Fixed inaccurate "±1 day buffer" comment
- **home/page.tsx**: `timeLabel` guards against null `startTime`/`endTime` values

---

## [2026-04-01] Feature — Meetings hub with Recall.ai integration

Full meetings feature across all platforms: calendar sync, Recall.ai bot recording, AI recaps, transcript Q&A, and second-brain integration.

### Backend (`apps/server`)

- **DB schema** (`schema.ts`): Added 4 tables — `meetIntegration`, `meeting`, `meetingMedia`, `meetingTranscript` with indexes.
- **Migration**: `0042_absurd_emma_frost.sql` generated.
- **Recall.ai client** (`lib/recall.ts`): `createRecallBot`, `getBotStatus`, `cancelBot`, `getBotTranscript` with retry logic.
- **Webhook** (`routes/recall-webhook.ts`): Handles `bot.status_change`, `recording.done`, `transcript.done` events.
- **tRPC meet router** (`trpc/routes/meet.ts`): `listMeetings`, `getMeeting`, `createMeeting`, `deleteMeeting`, `scheduleBot`, `cancelBot`, `generateSummary`, `askQuestion`, `syncFromCalendar`, `getIntegration`, `upsertIntegration`.
- **AI tools** (`routes/agent/tools.ts`): Added `listMeetings`, `getMeetingSummary`, `searchMeetingTranscript` tools for second-brain AI access.
- **Env** (`env.ts`): Added `RECALL_API_KEY`, `RECALL_API_BASE_URL`, `RECALL_WEBHOOK_SECRET`.
- **Types** (`types.ts`): Added `ListMeetings`, `GetMeetingSummary`, `SearchMeetingTranscript` to Tools enum.

### Web (`apps/mail`)

- **Routes** (`routes.ts`): Added `/mail/meetings` and `/mail/meetings/:meetingId`.
- **Navigation** (`config/navigation.ts`): Added "Meetings" with Video icon and `g + m` shortcut.
- **List page** (`meetings/page.tsx`): Time-grouped list, status filters, search, calendar sync button, empty state.
- **Detail page** (`meetings/[meetingId]/page.tsx`): Video player, AI recap, action items, transcript viewer, Q&A chat.

### macOS (`apps/macos`)

- **Navigation**: Added `.meetings` case to `MacPrimarySelection`, sidebar button, ⌘5 shortcut.
- **Service** (`Services/Meetings/MeetingsService.swift`): Full tRPC client for meetings CRUD + AI.
- **Views**: `MacMeetingsView.swift` (split list+detail), `MacMeetingDetailView.swift` (video, recap, transcript, Q&A).
- **Registration**: Added `meetingsService` to `MacAppServices`.

### iOS (`apps/ios`)

- **Navigation**: Added `.meetings` to `AppTab`, tab content in `MainTabView`.
- **Service** (`Services/Meetings/MeetingsService.swift`): Full tRPC client matching macOS.
- **Views**: `MeetingsListView.swift` (grouped list with search), `MeetingDetailView.swift` (video, recap, transcript, Q&A).
- **Registration**: Added `meetingsService` to `AppServices`.

## [2026-04-01] Fix — Code review bug-fix batch

### CHANGELOG

- Corrected "4 branches" → "5 branches" in iOS EmailInboxView entry.

### Backend (`apps/server`)

- `calendar.ts`: Added `scopeMissing: false` to non-Google early returns in `events` and `calendars` procedures so the shape is consistent.
- `settings.ts`: `save` mutation now validates existing settings through `userSettingsSchema.safeParse` before merging, eliminating the unsafe `as UserSettings` cast.
- `groups.ts`: `generateToken()` now uses URL-safe base64 (replaces `+`→`-`, `/`→`_` instead of stripping) for reliable 16-char output. `create` and `join` wrapped in transactions. `regenerateInvite` now calls `requireActiveGroup`. `listMessages` uses compound `timestamp:id` cursor. `generateGroupAIResponse` opens its own DB connection so it can run safely in a background `waitUntil` after the request connection closes.
- `sharing.ts`: Added `passwordSalt` guard in `get` and `import`. `update` now filters out revoked shares. `import` is now rate-limited. Rate-limiter comment clarified (per-IP bucketing handled by middleware).
- `mail-assistant.ts`: `listAssistantActivity` wraps `JSON.parse` in try/catch per key. `createGoogleCalendarEvent` adds `timeZone: 'UTC'` to start/end. Draft subject fallback changed from `undefined` to `'No Subject'`.
- `migrations/0041`: Removed 3 redundant B-tree indexes (`group_slug_idx`, `group_invite_token_idx`, `shared_conversation_slug_idx`) that duplicated existing UNIQUE constraints.

### Web (`apps/mail`)

- `calendar/page.tsx`: Removed redundant ternary `e.allDay ? new Date(e.startTime) : new Date(e.startTime)`.
- `mail-list.tsx`: Empty-inbox state now checks `!isConnectionLoading` to prevent flash before connection loads.
- `settings/sharing/page.tsx`: Added `'use client'` directive; clipboard `writeText` now properly awaited with error toast fallback.
- `group-chat-view.tsx`: `handleSend` restores message text on mutation error; `copyInviteLink` awaits clipboard with error toast.
- `share-conversation-modal.tsx`: `handleCopy` awaits clipboard with error toast; success message is conditional on visibility.
- `group-join/[token]/page.tsx`: Added `onError` handler and inline error message for join mutation.
- `share/[slug]/page.tsx`: Added `onError` handler and inline error message for import mutation.

### iOS (`apps/ios`)

- `AIChatView.swift`: Removed `.menuStyle(.borderlessButton)` — macOS-only API.
- `AIChatService.swift`: `moveConversation` captures value before spawning async `Task` to avoid stale index.
- `CalendarService.swift`: Replaced `hashValue` with stable packed-RGB extraction from CGColor components.
- `TaskCaptureService.swift`: Captures `folderId` before `context.delete`; marks unlinked tasks `.pendingUpload`.
- `EmailInboxView.swift`: Folder-change handler cancels debounce task before clearing `searchText` to prevent redundant `loadThreads` call.
- `ShareConversationSheet.swift`: Password validation guard added; `expiresInDays` now uses `apiValue` computed property.
- `GroupChatService.swift`: Replaced all `apiClient!` force-unwraps with a throwing `client()` helper; `createGroup` now matches returned group by id; added `GroupChatServiceError`.
- `ShareConversationService.swift`: Replaced `apiClient!` force-unwraps with `client()` helper; added `ShareConversationServiceError`.

### macOS (`apps/macos`)

- `MacAppServices.swift`: `syncSharedFolders` now guards on `authService.isAuthenticated`.
- `MacAssistantPanel.swift`: Removed `.swipeActions` (no-op in `ScrollView+LazyVStack`); moved Delete into ellipsis Menu.
- `CalendarService.swift`: Added `pruneFolderMap()` to remove stale event entries from UserDefaults.

## [2026-03-31] Feature — Proactive Mail Assistant across web + iOS + macOS

### Backend — shared assistant layer + settings policy

- Added `mailAssistant` tRPC router with per-thread recommendations (`getThread`), inbox nudges (`getInboxNudges`), manual apply actions (`createTaskFromSuggestion`, `createEventFromSuggestion`), draft generation (`generateDraft`), and assistant activity logging (`logActivity`, `getActivity`).
- Added shared `assistantAutomationPolicy` settings schema with defaults for summaries, task/event suggestions, smart nudges, auto-drafts, and the opt-in auto-send experiment.
- Settings now deep-merge the nested assistant policy so older settings payloads stay backward-compatible.
- Draft generation reuses the existing compose pipeline and thread context; assistant activity is stored in KV for lightweight audit history without a schema migration.

### Web — proactive thread + inbox UX

- Replaced the passive summary block with a visible `Mail Assistant` card in thread view: summary, action-item detection, risk/confidence badges, suggested tasks/events, reply draft action, research entry point, and copy/refresh controls.
- Added inline per-message assistant actions for task creation, event creation, assistant handoff, and research.
- Added inbox-level assistant nudges above the thread list so users see reply-needed / meeting-request / follow-up / draft-ready prompts before opening a thread.
- Added mail assistant controls to General Settings with recommended defaults, nested policy toggles, quiet hours, and allowed auto-send scenarios.

### iOS

- Added native assistant models plus email-service calls for thread recommendations, inbox nudges, task/event creation, and assistant draft generation.
- Email thread now shows a top-level assistant card with summarize, extract-task, create-event, draft-reply, ask-assistant, and research actions.
- Email inbox now surfaces compact assistant nudges above the thread list.
- AI Assistant settings now include mail-assistant automation toggles and persist them through shared backend settings.

### macOS

- Added native assistant models plus email-service calls for thread recommendations, inbox nudges, task/event creation, and assistant draft generation.
- macOS thread sheets now show a visible assistant card and inline assistant controls.
- macOS inbox now surfaces assistant nudges above the thread list.
- macOS settings now expose the assistant automation toggles and recommended preset.

**User-facing:** Mail now behaves more like an assistant than a passive inbox. Users can summarize threads, extract tasks, create events, draft replies, and act on proactive nudges across web, iOS, and macOS.

**Files:** `apps/server/src/lib/schemas.ts`, `apps/server/src/trpc/routes/settings.ts`, `apps/server/src/trpc/routes/mail-assistant.ts` (new), `apps/server/src/trpc/index.ts`, `apps/mail/components/mail/mail-display.tsx`, `apps/mail/components/mail/mail.tsx`, `apps/mail/app/(routes)/settings/general/page.tsx`, `apps/ios/Todus/Todus/Domain/MailAssistantModels.swift` (new), `apps/ios/Todus/Todus/App/AppServices.swift`, `apps/ios/Todus/Todus/Navigation/MainTabView.swift`, `apps/ios/Todus/Todus/Services/Email/EmailService.swift`, `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift`, `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`, `apps/ios/Todus/Todus/Features/Email/EmailComposeView.swift`, `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`, `apps/macos/TodusMac/Domain/MailAssistantModels.swift` (new), `apps/macos/TodusMac/App/MacAppServices.swift`, `apps/macos/TodusMac/App/MacRootView.swift`, `apps/macos/TodusMac/Services/Email/EmailService.swift`, `apps/macos/TodusMac/Views/Email/MacEmailThreadView.swift`, `apps/macos/TodusMac/Views/Email/MacEmailInboxView.swift`, `apps/macos/TodusMac/Views/Email/MacEmailComposeView.swift`, `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`, `TASK.md`

## [2026-03-31] Feature — Shared conversation permalinks + Group chats (web + iOS + macOS)

### Backend — DB + tRPC

- **4 new Drizzle tables**: `shared_conversation`, `group`, `group_member`, `group_message` — all with proper FKs, cascade rules, and indexes. Migration `0041_lame_emma_frost.sql` generated and applied.
- **`sharing` tRPC router** (6 procedures): `create`, `get`, `import`, `listMine`, `revoke`, `update`. Password hashing via Web Crypto PBKDF2 (100k iterations, SHA-256). Rate-limited public `get` (20 req/min via Upstash Redis).
- **`groups` tRPC router** (11 procedures): `create`, `getByInvite`, `join`, `leave`, `listMine`, `sendMessage`, `listMessages`, `get`, `update`, `kickMember`, `regenerateInvite`, `delete`. AI responses generated in background via `waitUntil`. Message rate-limited (30/min per user).
- Both routers registered in `apps/server/src/trpc/index.ts`.

### Web

- New routes: `/share/:slug` (public shared conversation), `/g/:token` (group invite join), `/settings/sharing` (manage shared links).
- `ShareConversationModal` component — title, visibility (public/protected), password, expiry.
- `GroupChatView` — 5-second `refetchInterval` polling with `TODO(realtime)` comment.
- Share button wired into `ai-sidebar.tsx`; group sidebar section added to `app-sidebar.tsx`.

### iOS

- `ShareConversationService` + `GroupChatService` (polling, `TODO(realtime)` marker).
- `ShareConversationSheet` — create share link from AI chat menu; success state with native `ShareLink`.
- `SharedConversationView` — read-only with password gate; opened via `todus://share?slug=...` deep link.
- `GroupListView` + `GroupChatView` (iOS) — create/join/leave groups, member avatars, polling composer.
- `AIChatView` Share menu item redirects to `ShareConversationSheet` when conversation is saved.
- Deep link `todus://share?slug=...` handled in `TodosApp.swift`.
- `AppServices` extended with `shareConversationService` and `groupChatService`.

### macOS

- `MacShareConversationPanel` — popover from AI assistant ellipsis menu.
- `MacGroupChatView` — HSplitView with member list + message area, polling.
- `MacGroupListSection` — sidebar section with create/join actions.
- `MacSidebarView` updated with `selectedGroupId` binding and Groups section.
- `MacRootView` shows `MacGroupChatView` in detail pane when a group is selected.
- `MacAppServices` extended with `shareConversationService` and `groupChatService`.

**Files:** `apps/server/src/db/schema.ts`, `apps/server/src/trpc/routes/sharing.ts` (new), `apps/server/src/trpc/routes/groups.ts` (new), `apps/server/src/trpc/index.ts`, `apps/mail/app/routes.ts`, `apps/mail/app/(full-width)/share/[slug]/page.tsx` (new), `apps/mail/app/(full-width)/group-join/[token]/page.tsx` (new), `apps/mail/components/ui/share-conversation-modal.tsx` (new), `apps/mail/components/ui/group-chat-view.tsx` (new), `apps/mail/components/ui/ai-sidebar.tsx`, `apps/mail/app/(routes)/settings/sharing/page.tsx` (new), `apps/ios/…/ShareConversationService.swift` (new), `apps/ios/…/GroupChatService.swift` (new), `apps/ios/…/ShareConversationSheet.swift` (new), `apps/ios/…/SharedConversationView.swift` (new), `apps/ios/…/GroupChatView.swift` (new), `apps/ios/…/AIChatView.swift`, `apps/ios/…/AppServices.swift`, `apps/ios/…/TodosApp.swift`, `apps/macos/…/MacShareConversationPanel.swift` (new), `apps/macos/…/MacGroupChatView.swift` (new), `apps/macos/…/MacSidebarView.swift`, `apps/macos/…/MacRootView.swift`, `apps/macos/…/MacAppServices.swift`

---

## [2026-03-31] Fix — C2: Web home page — distinguish "not connected" from empty state

### Web — `home/page.tsx`

- **Calendar section**: Replaces static "Connect Google Calendar" CTA with real `trpc.calendar.events` query for today. Shows live events with colored left border, time, and optional location. `scopeMissing = true` → re-auth button. No events → "No events today".
- **Email section**: Checks `threadsQuery.isError` to surface "Connect Gmail" CTA (backend returns `NOT_FOUND` when no connection) vs "Your inbox is empty" when connected with no threads.
- Added `CalendarEventRow` component for compact event rendering (colored border, time label, location).

**Files:** `apps/web/app/(routes)/mail/home/page.tsx`

---

## [2026-03-31] Feature — S1: Google Calendar integration (backend + web)

### Backend — `calendar.ts` + `trpc/index.ts` + `driver/google.ts`

- New `calendarRouter` with `events` and `calendars` queries — calls Google Calendar API v3 using `OAuth2Client` (auto-refresh via stored `refreshToken`)
- `calendar.readonly` scope added to Google driver's `getScope()` — included in all new auth flows
- 403 "scope missing" handled gracefully: returns `{ events: [], scopeMissing: true }` so the frontend can prompt a re-auth rather than surfacing an error

### Web — `calendar/page.tsx`

- Calendar page now fetches real Google Calendar events for the displayed month
- Right panel shows events (colored left border, time, location) above tasks; unified empty state
- Week overview shows blue dots on days with events
- `scopeMissing = true` → "Connect Google Calendar" banner with `authClient.linkSocial` re-auth
- Page title reverted to "Calendar" now that real events are shown

**Files:** `apps/server/src/trpc/routes/calendar.ts` (new), `apps/server/src/trpc/index.ts`, `apps/server/src/lib/driver/google.ts`, `apps/web/app/(routes)/mail/calendar/page.tsx`

---

## [2026-03-31] Feature — S3: iOS Settings navigation-based restructure

### iOS — `SettingsView.swift`

- Active Sessions → `SessionsSettingsView` sub-page; main settings shows session-count badge NavigationLink
- AI Assistant → `AIAssistantSettingsView` sub-page (two large TextEditors removed from main list); profile saved on `.onDisappear`
- Appearance → `AppearanceSettingsView` sub-page (vertical row list replaces cramped three-column picker); main settings shows current theme name as subtitle
- Removed unused `headerCell`, `valueCell`, `formatSessionDate`, `revokingSessionIDs`, `isRevokingAllSessions` from main view

**Files:** `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`

---

## [2026-03-31] UX Polish — web mail first-run and inbox clarity pass

- Reworked the first-run flow in `apps/mail` so onboarding no longer competes with inbox connection setup. The inbox tour now waits until the user has at least one connected account.
- Replaced the blocking connect-email modal with a dismissible setup card, so users can orient themselves or navigate to settings without being trapped in a modal on first load.
- Clarified primary inbox controls: the main search affordance now reads as `Search or filter mail`, the category dropdown is labeled `Filter inbox`, active filter counts use consistent wording, and the inbox/People toggle now explains what the People view does.
- Improved thread-list discoverability by keeping row actions lightly visible instead of fully hidden until hover, and upgraded empty states with clearer, action-oriented copy.
- Simplified thread-header hierarchy by making `Reply all` the obvious primary action and moving notes into secondary actions, while also making the AI entry point more concrete through updated tooltip/call-to-action language.
- Tightened onboarding copy to focus on immediate email tasks instead of vague marketing or future-looking messaging.

**User-facing:** First-time users get a calmer setup flow, inbox controls are easier to understand within a few seconds, and the main email actions are more obvious.

**Files:** `apps/mail/components/onboarding.tsx`, `apps/mail/components/connection/connection-wrapper.tsx`, `apps/mail/components/mail/mail.tsx`, `apps/mail/components/mail/mail-list.tsx`, `apps/mail/components/mail/thread-display.tsx`, `apps/mail/components/mail/note-panel.tsx`, `apps/mail/components/ai-toggle-button.tsx`, `TASK.md`

## [2026-03-31] Fix — iOS: email inbox 4-state branching (loading / error / empty / results)

### iOS — `EmailInboxView.swift`

- Added `errorState` view: `exclamationmark.triangle` icon, "Couldn't load \(folder)" title, backend error message as subtitle, "Try Again" button
- Body condition now has 5 branches: no-connection → skeleton (isLoading && empty) → **error** (errorMessage != nil && empty && !loading) → empty → thread list
- `emptyState` now branches: search-empty ("No results for X", Clear Search button) vs folder-empty (folder icon, Refresh button)
- Fixed bug: `searchBar.onSubmit` was calling `loadThreads(query:refresh:)` without `folder:` — now passes `selectedFolder.rawValue`

**Files:** `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`

## [2026-03-31] UX Polish — email folder parity on iOS and macOS

### iOS — `EmailInboxView.swift`

- Added `EmailFolder` private enum covering all 7 backend folders: inbox, drafts, sent, archive, snoozed, spam, bin (trash)
- Header title is now tappable — opens a `Menu` folder picker with icons, divided into primary (Inbox/Drafts/Sent) and secondary (Archive/Snoozed/Spam/Trash) groups
- Folder changes clear the search field and reload threads via `loadThreads(folder:refresh:)`
- Loading skeleton, empty state icon, and empty state title all reflect the active folder

### macOS — `MacRootView.swift` + `MacSidebarView.swift`

- Extended `EmailSection` enum with four new cases: `.archive`, `.snoozed`, `.spam`, `.bin` — each with a `title`, `systemImage`, and `isPrimary` flag
- Sidebar email sub-items now show icons alongside text (updated `SidebarChildItemButton` to accept optional `systemImage`)
- Primary folders (Inbox, Drafts, Sent) appear above a subtle divider; secondary folders below
- `MacEmailInboxView(folder: section.rawValue)` already routes the raw value to the backend — no additional changes needed

**Files:** `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`, `apps/macos/TodusMac/App/MacRootView.swift`, `apps/macos/TodusMac/App/MacSidebarView.swift`, `apps/macos/TodusMac/Views/Email/MacEmailInboxView.swift`

## [2026-03-31] Feature — web: shareable thread summary copy action

- Added a one-click `Copy summary` action to the thread summary card in `apps/mail/components/mail/mail-display.tsx`.
- The copied payload includes the thread subject, the AI summary, and a short Todus attribution footer so it can be pasted into email or Slack as a branded handoff.
- Added PostHog tracking for successful shares via `Thread Summary Shared`.

**User-facing:** Users can now turn an AI summary into a reusable share artifact without leaving the thread view.

**Files:** `apps/mail/components/mail/mail-display.tsx`, `TASK.md`

## [2026-03-31] Fix — privacy settings sender removal submits form

- Added `type="button"` to the trusted-sender removal control in `apps/mail/app/(routes)/settings/privacy/page.tsx` so clicking the remove icon no longer triggers the surrounding form submit.

**Files:** `apps/mail/app/(routes)/settings/privacy/page.tsx`, `TASK.md`

## [2026-03-31] Fix — categories settings state sync

- Updated `apps/mail/app/(routes)/settings/categories/page.tsx` so the local categories state rehydrates from `initialCategories` when fresh server data arrives, instead of relying on a stale effect dependency. Also removed the loose `any` type from the field-change prop.

**Files:** `apps/mail/app/(routes)/settings/categories/page.tsx`, `TASK.md`

## [2026-03-31] Fix — web root error boundary hook order

- Split the root error boundary in `apps/mail/app/root.tsx` so the 404 branch returns before any hooks and the Sentry/reporting side effects live in a dedicated child component. This removes the conditional hook call that violated `react-hooks/rules-of-hooks`.

**Files:** `apps/mail/app/root.tsx`, `TASK.md`

## [2026-03-31] UX Polish — cross-platform UX fixes (iOS, macOS, Web)

Comprehensive UX pass addressing discoverability, friction, and honesty gaps across all three live platforms.

### macOS

- **Removed non-functional Quick Filters** from tasks sidebar footer — buttons had nil closures and did nothing (`MacSidebarView.swift`)
- **Removed hardcoded email labels & calendar sources** from sidebar footer — "Important/Work/Personal" labels and calendar source pills were static UI not backed by real data (`MacSidebarView.swift`)
- **Removed non-functional toolbar filter menus** — email (All Mail/Unread/Flagged) and tasks (All/Today/Upcoming/Completed) filters had empty closures; "Mark All Read" is the only remaining email toolbar action (`MacRootView.swift`)
- **Removed dead notification bell** — popover showed hardcoded "No new notifications." placeholder (`MacRootView.swift`)
- **Confirmed Email and AI Assistant are already separate sections** in `MacSettingsView.swift` — no change needed

### iOS

- **Split Settings: "Email & AI" → separate "Email" + "AI Assistant" sections** — reduces cognitive load; unrelated settings no longer grouped (`SettingsView.swift`)
- **Replaced horizontal-scroll sessions table with vertical cards** — mobile-friendly layout with "This device" badge and per-session log out (`SettingsView.swift`)
- **Added skeleton loading state to email inbox** — differentiates loading vs empty vs error; `.redacted(reason: .placeholder)` blocks shown during initial fetch (`EmailInboxView.swift`)

### Web

- **Honest Calendar page labeling** — title changed from "Calendar" to "Tasks by Date" with "Calendar events coming soon" badge; misleading "Connect Google Calendar" link removed (`calendar/page.tsx`)
- **Quick Actions on Search page** — initial empty state now shows inline task-create field (type + Enter) and "Compose new email" button, matching macOS quick-action pattern (`search/page.tsx`)

**Files:** `apps/macos/TodusMac/App/MacSidebarView.swift`, `apps/macos/TodusMac/App/MacRootView.swift`, `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`, `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`, `apps/web/app/(routes)/mail/calendar/page.tsx`, `apps/web/app/(routes)/mail/search/page.tsx`

## [2026-03-31] Refactor — `resolveCurrentSessionId` Bearer guard clarity

- Replaced `!authHeader?.startsWith('Bearer ')` with `!authHeader || !authHeader.startsWith('Bearer ')` in `apps/server/src/trpc/routes/sessions.ts`. Behavior is unchanged (null/empty headers still take the hint/early-return path only), but the guard matches the real invariant before `authHeader.slice()` and narrows types explicitly.

**Files:** `apps/server/src/trpc/routes/sessions.ts`

## [2026-03-31] Fix — 3 targeted bugs: security nav, AI priority enum, prompt ordering

- **Security nav missing**: Added `navigation.settings.security` entry to `apps/web/config/navigation.ts` so the Active Sessions page (`/settings/security`) is reachable from the settings sidebar. Route and i18n key already existed; the nav link was the only missing piece.
- **Stale 'urgent' priority in AI tool definitions**: Removed `'urgent'` from the priority enum in both `create_task` and `update_task` tool definitions in `apps/server/src/routes/ai.ts`. The server tRPC schema (`tasks.ts`) only accepts `['none','low','medium','high']`; any AI-generated `priority: 'urgent'` would fail validation.
- **AI profile prepended before system prompt**: Flipped ordering in `apps/server/src/routes/agent/index.ts` (ZeroAgent) and `apps/server/src/routes/ai.ts` (`/ai/chat` and `/ai/call`) so the base system instructions appear first and user profile context is appended after, ensuring core rules are not shadowed by user content.

**User-facing:** Security page now appears in settings sidebar. AI task creation with priority no longer silently fails. AI assistant behavior is more stable when users set custom profiles.

**Files:** `apps/web/config/navigation.ts`, `apps/server/src/routes/ai.ts`, `apps/server/src/routes/agent/index.ts`

## [2026-03-31] Fix — server auth: prevent repeated onboarding email campaigns

- Persist the `welcomeEmailSent` guard before dispatching onboarding campaigns so a partial Resend failure can no longer replay the entire sequence on the next login.
- Made onboarding campaign dispatch best-effort per email so one failed scheduled message does not block the rest of the sequence or reopen the send gate.

**User-facing:** New and returning users should stop receiving repeated "Welcome", "Todus Pro is here", and related onboarding emails on every login.

**Files:** `apps/server/src/lib/auth.ts`, `TASK.md`

## [2026-03-31] Feature — web: Full iOS/macOS visual parity pass (Tasks board/table, Home redesign, Chat history, Calendar quick-add)

### Tasks page (`/mail/tasks`) — full rewrite

- **View mode picker**: segmented control (List / Board / Table) at top right
- **Horizontal folder pill strip**: scrollable row of pills replaces old sidebar layout — "All" + each folder + "+" add folder button
- **Board view** (kanban): 3 draggable columns (To Do / Doing / Done) using `@dnd-kit/core`. Drag cards between columns to update `status` via `tasks.update`. `DragOverlay` renders the card while dragging.
- **Table view**: compact single-line `<table>` rows (checkbox, title, priority, status, due, folder, menu) — dense Linear-style view
- **Quick-add row**: inline text input at top of list view — Enter creates task with current folder pre-selected
- **Task detail Sheet**: clicking a task title opens a `<Sheet side="right">` with full metadata (title, description, priority, status, due date, folder), edit + delete buttons
- **TypeScript fix**: `isDueDateWarning` now accepts `string | Date | null | undefined` since tRPC can return `Date` objects

### Home page (`/mail/home`) — redesign

- **Section headers**: iOS-style `SectionHeader` component — icon + title + count badge + "See all" link + optional "+" button
- **Today's Events section**: "Connect Google Calendar" CTA card (dashed border, links to Settings → Connections). No fake data shown since backend Calendar API isn't wired yet.
- **Sections**: Events → Due Tasks → Recent Emails (matches iOS order)
- **Card containers**: each section wrapped in `rounded-xl border bg-card px-4 py-4`
- **Greeting**: larger `text-[22px]` heading with date subtitle

### Chat page (`/mail/chat`) — conversation history + markdown

- **Left sidebar** (hidden on mobile): `w-56` conversation list from `ai.listConversations`. Each row shows title + relative date. Active row highlighted with `bg-accent`.
- **Load conversation**: clicking a past chat loads its messages via `ai.getConversation` and restores to `setMessages()`
- **Auto-save**: on first assistant response (not mid-stream), saves conversation with title = first 60 chars of user's first message via `ai.saveConversation`
- **Delete**: hover → MoreHorizontal → dropdown → Delete triggers `ai.deleteConversation`, refreshes sidebar
- **Markdown**: AI responses rendered with `react-markdown` + `remark-gfm` inside `prose prose-sm dark:prose-invert` container (wrapped in div — react-markdown v10 doesn't accept className directly)
- **AI bubble style**: `border bg-card` instead of plain `bg-muted` for visual separation

### Calendar page (`/mail/calendar`) — polish + features

- **Inline quick-add row**: always-visible input at top of day panel — Enter creates task with `dueDate = selectedDate`
- **Connect Google Calendar CTA**: dashed-border card in left sidebar below week overview, links to Settings → Connections
- **Week overview**: dates with tasks show count badge
- **Empty state**: shows link to Tasks page
- **Header**: slimmer `py-3.5` consistent with other page headers

**Files:**

- `apps/web/app/(routes)/mail/tasks/page.tsx` — full rewrite
- `apps/web/app/(routes)/mail/home/page.tsx` — full rewrite
- `apps/web/app/(routes)/mail/chat/page.tsx` — full rewrite
- `apps/web/app/(routes)/mail/calendar/page.tsx` — full rewrite
- `apps/web/config/navigation.ts` — Email expandable parent + icon updates
- `apps/web/components/ui/nav-main.tsx` — NavItemExpandable, NavChildRow, removed feedback link
- `apps/web/components/ui/app-sidebar.tsx` — removed dead badge mutations
- `apps/web/components/ai-toggle-button.tsx` — circular FAB polish

## [2026-03-30] Feature — web: iOS/macOS feature parity (Folders, AI Chat, Global Search)

- **Task Folders**: Tasks page now has a folder sidebar (create/rename/delete folders, filter tasks by folder, move tasks to folders via dropdown). Backend `folders.list/create/update/delete` tRPC routes fully wired.
- **AI Chat page** (`/mail/chat`): Standalone full-page chat using `useAgent` + `useAgentChat` from Cloudflare `agents` SDK. Connects to `ZeroAgent` Durable Object via WebSocket. Example queries, streaming indicator, stop button.
- **Global Search page** (`/mail/search`): Searches both emails (via `mail.listThreads` with `q` param) and tasks (via `tasks.list` with `search` param) simultaneously. Tabbed result view (All / Emails / Tasks), debounced input, empty/loading states.
- **Navigation**: Added AI Chat and Search items to sidebar "Organize" section with keyboard shortcuts. Added `navigation.sidebar.chat` and `navigation.sidebar.search` i18n keys.
- **Routes**: Registered `/mail/chat` and `/mail/search` in `routes.ts`.

**Files:** `apps/web/app/(routes)/mail/tasks/page.tsx`, `apps/web/app/(routes)/mail/chat/page.tsx` (new), `apps/web/app/(routes)/mail/search/page.tsx` (new), `apps/web/app/routes.ts`, `apps/web/config/navigation.ts`, `apps/web/messages/en.json`

## [2026-03-31] Fix — web: invalidate all `tasks.list` queries after task mutations

- Task updates from mail home, calendar, and shared `TaskItem` now call `queryClient.invalidateQueries(trpc.tasks.list.queryFilter())` so every cached `tasks.list` variant (filters, sort, limit) refetches instead of only the one matching a fixed `queryKey({ limit: N })`.
- Mail tasks page `invalidate()` uses the same `queryFilter()` pattern (replacing a path-prefix `predicate` that relied on reference equality between fresh and cached `queryKey[0]` arrays).

**User-facing:** Lists and filters stay in sync after toggling or editing tasks from any surface.

**Files:** `apps/web/app/(routes)/mail/tasks/page.tsx`, `apps/web/app/(routes)/mail/home/page.tsx`, `apps/web/app/(routes)/mail/calendar/page.tsx`, `apps/web/components/tasks/task-item.tsx`, `apps/web/task-item.tsx`

## [2026-04-03] Fix — iOS AI chat input: layout redesign, freeze fix, expand button

- Redesigned chat input to two-row layout: full-width text field on top, button row below. Eliminates the squeezed text field issue and aligns text to the left edge.
- Fixed 9+ second freeze caused by a GeometryReader layout cycle — the old single-row HStack toggled `inputAtMaxHeight` which changed text field width → height → retrigger → infinite loop. New layout isolates text and buttons into separate VStack rows.
- Fixed transcribe button freezing the UI by moving `AVAudioSession.setActive` off the main actor with `Task.detached` in `VoiceController.beginAudioSession()`.
- Fixed full-screen compose sheet causing a 5-second hang by delaying keyboard focus until after the sheet presentation animation finishes (~350ms).
- Full-screen expand button is now only shown when the text input has reached its maximum height (≥118pt), with consistent 30×30 sizing matching other buttons.
- Reduced excessive vertical padding in the input box.

**Files:** `apps/ios/Todus/Todus/Features/Voice/VoiceInputButton.swift`, `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`

## [2026-03-31] Fix — shared keychain auth remains backward compatible

- Restored backward-compatible reads for legacy account-only Keychain items after adding the bundle service namespace.
- New writes still use the namespaced keychain entry, but upgrade installs now fall back to the previous storage shape so persisted bearer tokens and AI chat history survive the rollout.

**Files:** `packages/swift-auth/Sources/TodusAuth/KeychainHelper.swift`

## [2026-03-30] Feature — active sessions management in `apps/web`, iOS, and macOS

- Added a new backend `sessions` tRPC router with `list`, `revoke`, and `revokeAll`, backed by a new `mail0_session_metadata` table for coarse device/location metadata and last-seen tracking.
- Replaced the `apps/web` security placeholder with a real Active Sessions table showing `Device`, `Location`, `Created`, `Updated`, and per-session `Log out`, plus a `Log out all devices` action.
- Added matching Active Sessions management UI to iOS and macOS settings so signed-in devices can be reviewed and revoked from native clients too.
- Improved native current-session detection by resolving raw Better Auth session tokens from the session table when cookie session lookup is unavailable, and by forwarding the Better Auth `session.id` through the native OAuth handoff for JWT-based native sessions.
- Intentionally left cross-device live sync work out of this change set; that architecture remains a separate follow-up because it touches tasks, settings, AI state, and native persistence broadly.

**Files:** `apps/server/src/db/schema.ts`, `apps/server/src/db/migrations/0040_stiff_living_lightning.sql`, `apps/server/src/main.ts`, `apps/server/src/trpc/index.ts`, `apps/server/src/trpc/routes/sessions.ts`, `apps/web/app/(routes)/settings/security/page.tsx`, `apps/ios/Todus/Todus/Services/API/TodosAPIClient.swift`, `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`, `apps/macos/TodusMac/Services/API/TodosAPIClient.swift`, `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`, `packages/swift-auth/Sources/TodusAuth/AuthService.swift`, `TASK.md`

## [2026-03-30] Fix — archived RN parity and safety cleanup

- Hardened the archived RN auth, settings, and mail flows against stale optimistic state, unhandled URL opening errors, and unsafe persistence failures.
- Removed raw email from native PostHog identification, added safer Postgres healthcheck behavior in production compose, and closed Hyperdrive connections in the server auth token path.
- Updated shared compose/mail helpers and several settings screens to handle loading, error, and accessibility cases more defensively.

**Files:** `apps/server/src/main.ts`, `docker-compose.prod.yaml`, `apps/archived/archived-rn/...`

## [2026-03-30] Fix — native Google OAuth now returns a JWT bearer token for iOS/macOS

- Updated `/api/auth/mobile-token` to mint a JWT via Better Auth's `jwt()` plugin (`auth.api.getToken`) instead of forwarding the raw session token from the browser session.
- Kept the server auth middleware fallback paths in place, but the native callback now receives the JWT format that `/api/auth/me` already verifies directly.
- Updated the shared native auth comments so the callback token format is documented correctly again.

**Files:** `apps/server/src/main.ts`, `packages/swift-auth/Sources/TodusAuth/AuthService.swift`

## [2026-03-30] Fix — macOS centralized sign-out now clears email state before auth reset

- Updated the macOS `MacAppServices.signOut()` path to call `emailService.resetForSignOut()` before `authService.signOut()`.
- Removed the stale TODO from the centralized sign-out method so logout behavior now matches the sidebar and settings call sites that already route through this method.
- This prevents cached email threads, pagination tokens, connection status, and email errors from surviving logout and leaking into the next user session.

**Files:** `apps/macos/TodusMac/App/MacAppServices.swift`

## [2026-03-30] Fix — native auth session-expired state now survives sign-out, and Keychain save failures are observable

- Reordered the shared native auth invalid-session flow so `signOut()` runs before the session-expired flag and user-facing error are set, which preserves the warning banner/message instead of clearing them immediately.
- Applied the same ordering in persisted-session restoration so invalid saved sessions now leave the app in a consistent expired state after sign-out.
- Upgraded shared Keychain writes to return success/failure and log OSStatus details instead of silently ignoring `SecItemAdd` / `SecItemDelete` failures.
- Updated iOS and macOS AI conversation persistence to check the new Keychain write result and log failures instead of dropping them silently.
- Verified the macOS project `LastUpgradeCheck = 2640` already matches the installed Xcode 26.4 toolchain, so no project file change was required.

**Files:** `packages/swift-auth/Sources/TodusAuth/AuthService.swift`, `packages/swift-auth/Sources/TodusAuth/KeychainHelper.swift`, `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`, `apps/macos/TodusMac/Services/AI/MacAIChatService.swift`

## [2026-03-30] Fix — Cloudflare install now respects the web workspace lockfile

- Regenerated `pnpm-lock.yaml` so the `apps/web` `uuid` / `@types/uuid` dependency entries match `apps/web/package.json` again.
- Kept the dependency update scoped to the lockfile only; no app source changes were required for this deploy fix.

**Files:** `pnpm-lock.yaml`

## [2026-03-30] Fix — macOS search modal now searches calendar events and opens real actions

- Wired the macOS search modal to actual app callbacks so quick actions now open task creation, email compose, and new event flows instead of rendering inert rows.
- Added calendar event loading and search indexing to the modal so event names from the home dashboard now appear in search results.
- Improved the empty state with actionable suggestions and tap targets for common follow-up actions.
- Added direct navigation for search results so task, email, and event rows move the user into the right surface instead of doing nothing.

**Files:** `apps/macos/TodusMac/Views/Search/MacSearchView.swift`, `apps/macos/TodusMac/App/MacRootView.swift`

## [2026-03-30] Fix — macOS native auth now verifies session before entering the app shell

- Hardened the shared native `AuthService` so Google/Apple/OTP callbacks no longer mark the app as authenticated from token presence alone.
- Added post-callback `/api/auth/me` verification with short retry backoff to absorb the native OAuth handoff window before profile hydration completes.
- Added callback deduping so macOS dual callback entrypoints cannot race the same token through auth completion twice.
- Added explicit persisted-session restoration on macOS launch so stale Keychain state is rejected before the main shell renders.
- Namespaced native Keychain entries by bundle-specific service to make session storage deterministic across iOS/macOS and to make full local resets reliable.
- Added a DEBUG-only auth section in macOS Settings showing auth state, token preview, session-expired flag, and profile email for faster diagnosis.

**Files:** `packages/swift-auth/Sources/TodusAuth/AuthService.swift`, `packages/swift-auth/Sources/TodusAuth/KeychainHelper.swift`, `apps/macos/TodusMac/App/MacRootView.swift`, `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`, `apps/macos/README.md`, `TASK.md`

## [2026-03-30] Fix — macOS sidebar profile menu now opens settings

- Removed the no-op `Profile` item from the macOS sidebar account dropdown.
- Wired the profile menu entry to the existing macOS settings overlay so it now opens real profile/account controls.
- Kept the separate gear icon and keyboard shortcut as alternate settings entry points.

**Files:** `apps/macos/TodusMac/App/MacSidebarView.swift`, `apps/macos/README.md`

## [2026-03-30] Polish — macOS Calendar UI Round 5

- **Tap-to-create on time grid:** Tapping empty space in Day/Week time grid opens Apple Calendar's new event dialog at that time (snapped to 30-min slot). Uses `x-apple-calevent://new` URL scheme.
- **Segmented control visibility:** Replaced invisible `.thinMaterial` highlight with solid opaque pill (`Color(white: 0.22)` dark, white light) + shadow. Outer track uses matching solid color (`Color(white: 0.13)` dark) instead of `.ultraThickMaterial`.
- **Unified header controls:** Nav arrows, Today button, and segmented picker all use the same `controlBg` color and `headerControlHeight` (30pt). No more mismatched materials/heights.
- **Month view: prev/next month days visible muted:** Empty cells at month start/end now show actual dates from the previous/next months at 35% opacity — matching Apple Calendar behavior.
- **Month view: instant transitions:** Removed animation on month navigation. `.animation(.none, value: selectedDate)` on the grid prevents the "circus" effect of cells moving around.
- **Month view: scrollable:** Grid remains wrapped in ScrollView for overflow.

**Files:** `MacCalendarView.swift`, `CalendarTimeGridView.swift`

## [2026-03-30] Fix — macOS `EmailService.resetForSignOut()` (compile unblock)

- Implemented the missing `resetForSignOut()` on macOS `EmailService` so callers that clear cached threads, pagination, errors, and connection flags after sign-out resolve at link time.
- **Impact:** Fixes a hard build failure (undefined symbol) once logout/delete-account paths reference this API; unrelated to calendar UI work beyond sharing the same release.

**Files:** `apps/macos/TodusMac/Services/Email/EmailService.swift`

## [2026-03-30] Fix — macOS logout now resets email state before auth sign-out

- Centralized macOS sign-out in `MacAppServices.signOut()` so logout now mirrors the iOS flow.
- Added the missing `emailService.resetForSignOut()` call before `authService.signOut()` to clear threads, connection status, and error state on logout.
- Updated both macOS logout entry points to call the shared service helper:
  - Settings confirmation dialog
  - Sidebar user menu
- Also switched the macOS delete-account flow to the same helper so it leaves the app in a clean post-sign-out state.

**Files:**

- `apps/macos/TodusMac/App/MacAppServices.swift`
- `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`
- `apps/macos/TodusMac/App/MacSidebarView.swift`

## [2026-03-30] Fix — macOS/iOS native apps: user profile not loading after OAuth login

**Root cause (3 layers):**

1. Better Auth's HTTP `/auth/get-session` returns `null` for bearer-token requests (200 status, body: `null`)
2. The Hono middleware's JWT fallback tried to verify the 32-char session token as a JWT → threw silently
3. Variable shadowing: `const session = await auth.api.getSession()` shadowed the Drizzle `session` schema table, so the session token DB lookup used the wrong object

**Fix:**

- Renamed middleware variable to `authSession` to avoid shadowing the Drizzle `session` schema import
- Added session token DB lookup fallback: when JWT verification fails, looks up the raw token in the `session` table and resolves the user
- Added `GET /api/auth/me` endpoint that returns `c.var.sessionUser` from middleware context
- Updated shared `fetchUserProfile()` to use `/api/auth/me` instead of `/api/auth/get-session`
- Added `.task(id: isAuthenticated)` to MacRootView so profile fetch re-runs after login
- Added `.task { fetchUserProfile() }` to MacSettingsView

**Files:**

- `apps/server/src/main.ts` — `authSession` rename, session token lookup fallback, `/api/auth/me` endpoint
- `packages/swift-auth/Sources/TodusAuth/AuthService.swift` — Use `/auth/me`, debug logging
- `apps/macos/TodusMac/App/MacRootView.swift` — `.task(id: isAuthenticated)` for profile fetch
- `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift` — `.task { fetchUserProfile() }` on open

**Requires:** Backend redeployment (`pnpm deploy:backend`)

## [2026-03-30] Fix — iOS create-sheet attachment fallback and board regrouping

- Forwarded the captured attachment list into event creation fallback paths so failed calendar permission or event-creation errors still preserve user-selected attachments when creating a task instead.
- Restored the Kanban regroup observer using a task signature derived from each task's id, status, and folder so in-place SwiftData mutations move cards between columns again.

**Files:** `apps/ios/Todus/Todus/Navigation/CreateSheet.swift`, `apps/ios/Todus/Todus/Features/Tasks/BoardView.swift`

## [2026-03-30] Fix — iOS hang triage instrumentation and shell pressure reduction

- Deferred non-critical root startup work so launch no longer immediately competes with reminders import/sync and legacy auth-upgrade work.
- Switched the iOS shell back to rendering only the active tab, reducing hidden SwiftUI invalidation and background work during tab switches, focus changes, and general interaction.
- Added Instruments-friendly trace points around app initialization, deferred startup, tab switching, SwiftData saves, email thread loading, and reminders sync/import.
- Cached bearer tokens in-memory inside the shared native auth service and moved profile/token metadata persistence off the synchronous main-actor path to reduce Security/Keychain stalls.
- Prevented the email inbox from re-running its full initial fetch every time the tab becomes visible, and fixed a create-sheet fallback path so event creation failures preserve attachments when falling back to task capture.

**Files:** `TodosApp.swift`, `RootView.swift`, `MainTabView.swift`, `AppServices.swift`, `AppLogger.swift`, `EmailService.swift`, `EmailInboxView.swift`, `TaskCaptureService.swift`, `BoardView.swift`, `CreateSheet.swift`, `AuthService.swift`

## [2026-03-30] Fix — native sync, calendar, and accessibility cleanup

- Kept the marketing home avatar text consistent with the existing `adam.jpg` asset in both web shells.
- Restored a 44pt task-row checkbox hit area, removed the root macOS focus-ring suppression, and added a visible focus style to the Gmail connect button.
- Made macOS calendar month/all-day event pills tappable, tightened the time-grid math, and disabled the misleading empty delete actions.
- Added conversation-delete persistence so local removals survive sync, plus retry handling for pending backend deletes on iOS/macOS.
- Hardened the backend conversation upsert against cross-user overwrite, and aligned the latest migration with task checks, timestamp triggers, OAuth foreign keys, and the writing-style matrix column rename.

**Files:** `HomeContent.tsx` (web + mail), `TaskRowView.swift`, `CreateSheet.swift`, `TodosAPIClient.swift` (iOS + macOS), `MacRootView.swift`, `MacTheme.swift`, `MacEmailInboxView.swift`, `CalendarEventBlockView.swift`, `CalendarTimeGridView.swift`, `MacCalendarView.swift`, `AIChatService.swift` (iOS + macOS), `schema.ts`, `0039_brainy_junta.sql`, `0039_snapshot.json`, `conversations.ts`

## [2026-03-30] Copy — Founder / demo names: Adam → Ludvig

- Marketing home mock UI, About founders copy, HR demo row, and AI brain fallback sample thread now use **Ludvig** (abbreviated **Ludvig H** in HR mock data) instead of Adam / Adam G.
- **Unchanged:** `Scarlett Adams` in mail demo data (surname, not the first name Adam).

**Files:** `HomeContent.tsx` (mail + web), `about.tsx` (mail + web), `hr.tsx` (mail + web), `brain.fallback.prompts.ts`

## [2026-03-30] Feature — Year view + Apple Calendar glass segmented control

- **Year view:** New infinitely-scrollable vertical year view showing 21 years (±10) as 4×3 grids of mini-month calendars. Each mini-month shows day numbers, today circled in red, event dot indicators (accent color), weekday initials. Tap a mini-month → navigate to Month view for that month. Auto-scrolls to current year on appear.
- **Glass segmented control:** Replaced native `Picker(.segmented)` with custom `CalendarViewModePicker` using Apple Calendar-style glass/material design — `.ultraThickMaterial` outer pill, `.thinMaterial` selected highlight, `matchedGeometryEffect` for smooth animated sliding, 4 segments (Day/Week/Month/Year). Respects light/dark mode via SwiftUI Material.
- **Header buttons:** Nav arrows and "Today" button now use `.ultraThinMaterial` glass backgrounds instead of solid `surfaceCard` — matches the new glass aesthetic across all header controls.
- **Control sizing:** Unified `headerControlHeight` to 28pt for better tap targets.

**Files:** `MacCalendarView.swift`

## [2026-03-30] Fix — macOS Calendar UI Round 4

- **Week view header too tall (ROOT CAUSE):** `Color.clear.frame(width:)` gutter spacer expanded vertically — replaced with `Text("")` + `.fixedSize(horizontal: false, vertical: true)` wrapper
- **Header buttons:** Nav arrows now fully circular (24pt `Circle()`), "Today" pill same 24pt height, all controls aligned
- **Month view scrolling:** Wrapped LazyVGrid in `ScrollView(.vertical)` inside GeometryReader
- **Event deduplication:** Holidays from multiple calendars deduplicated by title+date
- **Day view tint:** Removed blueish accent highlight, now neutral
- **Segmented picker:** Fixed text wrapping with `.labelsHidden()` + wider frame

**Files:** `MacCalendarView.swift`, `CalendarService.swift`, `CalendarTimeGridView.swift`

## [2026-03-30] Redesign — Unified Create Sheet (merged CaptureComposer into CreateSheet)

**Problem:** Two competing input systems (CaptureComposer in tasks tab + CreateSheet global overlay) overlapped visually. CaptureComposer sat under the tab bar and was unusable. CreateSheet lacked attachments, voice, and slash commands.

**Solution:** Removed CaptureComposer from tasks tab entirely. Merged all its features into CreateSheet:

- Attachments (photo picker, camera, file picker) with inline thumbnails
- Voice transcription (VoiceInputButton)
- Slash commands (/due-today, /due-tomorrow, /due-next-week, /in-one-hour)
- Image paste handling (PasteHandlingTextInput)
- Keyboard-aware positioning

**Visual improvements:**

- Scrim opacity 0.10 → 0.45 (clearly distinguishable modal overlay)
- Text input 28pt → 16pt (compact, not oversized)
- Default type always "Auto" (AI decides) regardless of which tab
- Tight, clean toolbar with folder/date/voice/send in a single row

**Files:**

- `CreateSheet.swift` — Major rewrite with all merged features
- `TasksTabView.swift` — Removed CaptureComposer and keyboard observer
- `MainTabView.swift` — Removed defaultType parameter and method
- `CaptureComposer.swift` — Removed CaptureComposer struct; kept shared types (RichComposerInput, PasteHandlingTextInput, CameraPicker)

## [2026-03-30] Fix — macOS/iOS user profile not loading after login (shows "User" / "?")

**Root cause:** Better Auth's HTTP `/auth/get-session` endpoint returns `null` for bearer-token-authenticated requests. The Hono middleware's `auth.api.getSession()` call resolves bearer tokens correctly (tRPC routes work), but the HTTP handler doesn't — so `fetchUserProfile()` always got `null` back.

**Fix:**

- Added `/api/auth/me` endpoint on backend that returns `c.var.sessionUser` from the middleware context (which properly resolves bearer tokens)
- Updated `fetchUserProfile()` in shared AuthService to use `/api/auth/me` instead of `/api/auth/get-session`
- Added `.task(id: isAuthenticated)` to MacRootView so profile fetch re-runs after login (not just on initial view appear)
- Added `.task { fetchUserProfile() }` to MacSettingsView to refresh on settings open

**Files:**

- `apps/server/src/main.ts` — New `/api/auth/me` endpoint
- `packages/swift-auth/Sources/TodusAuth/AuthService.swift` — Use `/auth/me`, added debug logging
- `apps/macos/TodusMac/App/MacRootView.swift` — `.task(id: isAuthenticated)` for profile fetch
- `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift` — `.task { fetchUserProfile() }` on open

**Requires:** Backend deployment before the native apps can fetch profile data.

## [2026-03-30] Fix — macOS Calendar UI Round 3 bugs

- **Week view all-day events:** Changed from vertical column layout to horizontal per-day-column layout matching Apple Calendar — each day column now shows its own all-day events, preventing the massive tall header
- **Event deduplication:** Holidays and events appearing from multiple calendar sources (e.g. iCloud + Google) are now deduplicated by title+date, keeping only the first occurrence
- **Day view background tint:** Removed blueish accent tint from today's column highlight — now uses neutral `Color.primary.opacity(0.015)` instead of `MacTheme.accent.opacity(0.025)`
- **Segmented picker wrapping:** Fixed "Vie\nw" text wrapping by removing the "View" label text, adding `.labelsHidden()`, and widening frame from 170→180pt

**Files:** `MacCalendarView.swift`, `CalendarService.swift`, `CalendarTimeGridView.swift`

## [2026-03-30] Fix — iOS calendar icon stretched + tasks page too bulky

- **Calendar icon:** Added explicit height to `AppleCalendarIconView` so GeometryReader doesn't stretch vertically
- **Search bar:** Reduced vertical padding (9→6) and changed to Capsule shape for a slimmer, rounded look
- **Task rows:** Reduced vertical padding (8→5) and checkbox height (44→32) for more compact list items
- **Completed task rows:** Reduced vertical padding (12→8) and corner radius (16→14)
- **Header spacing:** Reduced view mode picker vertical padding (12→4)

**Files:** `BrandIcons.swift`, `TasksTabView.swift`, `TaskRowView.swift`, `InboxView.swift`

## [2026-03-30] Feature — Backend-synced AI conversation history

Conversations now sync to the backend via tRPC, enabling cross-device and cross-reinstall persistence.

### Backend

- **New table:** `mail0_ai_conversation` (id, userId, title, messages JSONB, timestamps)
- **New tRPC endpoints:** `ai.listConversations`, `ai.getConversation`, `ai.saveConversation`, `ai.deleteConversation`
- **Migration:** `0039_brainy_junta.sql`

### iOS & macOS

- Conversations synced to backend on save/delete (fire-and-forget)
- On launch: loads local cache first, then merges with backend
- Local cache moved from UserDefaults → Keychain (survives reinstall)
- Auto-migration from old UserDefaults storage

**Files:** `apps/server/src/db/schema.ts`, `apps/server/src/trpc/routes/ai/conversations.ts`, `apps/server/src/trpc/routes/ai/index.ts`, `apps/server/src/db/migrations/0039_brainy_junta.sql`, `apps/ios/.../AIChatService.swift`, `apps/macos/.../MacAIChatService.swift`

## [2026-03-30] Fix — Bearer token rotation capture (root cause of "Session expired")

Better Auth's bearer plugin returns a rotated session token via `set-auth-token` header when `updateAge` extends the session. Neither iOS nor macOS captured this — they kept the old token until it expired, causing 401s.

- **`AuthService.swift`**: Added `captureRotatedToken(from:)` — checks responses for `set-auth-token` and stores new token. Called from `attemptSilentRefresh()` and `fetchUserProfile()`.
- **`TodosAPIClient.swift` (iOS + macOS)**: Calls `captureRotatedToken` on every API response.
- **`AIChatService.swift` / `MacAIChatService.swift`**: Capture on SSE stream responses.
- **`KeychainHelper.swift`**: Added `saveData`/`readData` for Data blobs.

## [2026-03-30] Fix — macOS AI chat 401 handling (silent refresh parity with iOS)

`MacAIChatService` now mirrors iOS: on HTTP 401 from `/api/ai/chat`, call `attemptSilentRefresh()` before treating the session as dead. Success → user message to retry; failure → `isSessionExpired = true` and re-auth prompt.

**Files:** `apps/macos/TodusMac/Services/AI/MacAIChatService.swift`

## [2026-03-30] Fix — macOS settings and assistant panel compile cleanup

Resolved the current macOS Xcode warnings/errors blocking the `TodusMac` build:

- restored the branded service-row helper used by `MacSettingsView`
- added the missing Apple Reminders connection flag used by the settings UI
- replaced the explicit `Selector(("showHelp:"))` call with `#selector`
- removed ineffective `nonisolated(unsafe)` storage annotations from `MacVoiceController` and updated the speech callback to hop back to the main actor

**Files changed:**

- `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`
- `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`

## [2026-03-30] Fix — `@zero/web` index route & routing parity with `apps/mail`

**Symptom:** Visiting `http://localhost:3000/` showed a non-interactive calendar stub with no sidebar or mail chrome.

**Root cause:** `react-router.config.ts` uses `appDirectory: 'app'`, so `index('page.tsx')` resolves to **`app/page.tsx`**, which had been a placeholder calendar — not the marketing `HomeContent` shell from `apps/mail`. The experimental `app-layout.tsx` wrapper also did not apply to `/`, so the index never matched the unified shell.

**Fix:** Replaced `app/page.tsx` with the same pattern as `apps/mail` (`HomeContent` + `clientLoader` redirect to `/mail/inbox` when authenticated). Replaced **`app/routes.ts`** with the same tree as **`apps/mail/app/routes.ts`** (removed outer `app-layout` and `/home`/`/tasks`/`/calendar` routes under that layout). Removed duplicate/orphan files: root `apps/web/page.tsx`, `app/app-layout.tsx`, `(routes)/home|tasks|calendar/page.tsx`.

**User-facing:** Logged-in users land in the real mail app (`AppSidebar`, folders, working mail UI). Guests still get the marketing home.

## [2026-03-30] Fix — iOS AI chat session expired error & cross-reinstall persistence

### Session expired despite being logged in

- **Root cause:** `AIChatService` returned "Session expired" immediately on HTTP 401 without attempting a silent session refresh. `TodosAPIClient` already handled this correctly.
- **Fix:** On 401, attempt `authService.attemptSilentRefresh()` first. If refresh succeeds, prompt user to retry. If it fails, mark `isSessionExpired = true` for proper re-auth flow.
- **File:** `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`

### Chat history lost on reinstall

- **Root cause:** Conversations stored in `UserDefaults` which is wiped when the app is uninstalled.
- **Fix:** Moved conversation persistence to Keychain (`KeychainHelper.saveData`/`readData`), which survives app reinstalls. Includes automatic migration from old `UserDefaults` storage.
- **Files:** `packages/swift-auth/Sources/TodusAuth/KeychainHelper.swift` (added Data methods), `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`

## [2026-03-30] Fix — macOS app shows "User" with "?" avatar after Google OAuth login

**Root cause:** macOS app never called `fetchUserProfile()` on launch or when settings opened. The iOS app calls it in both `RootView.task{}` and `SettingsView.task{}`, but the macOS equivalents were missing these calls. The only profile fetch happened in `completeAuthentication()`'s fire-and-forget `Task{}`, which could silently fail during the auth→main view transition.

**Fix:** Added `fetchUserProfile()` calls to match iOS behavior:

- `MacRootView.swift` — new `.task{}` that fetches profile on app start
- `MacSettingsView.swift` — new `.task{}` that refreshes profile when settings opens

**Files changed:**

- `apps/macos/TodusMac/App/MacRootView.swift` — Added `.task { await services.authService.fetchUserProfile() }`
- `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift` — Added `.task { await services.authService.fetchUserProfile() }`

## [2026-03-30] Polish — iOS AI assistant input bar refinements

Five targeted UX improvements to the iOS AI chat input area:

- **Tighter button sizing**: Standardized all action buttons (waveform, mic, send) to consistent 34×34 outer frames with 6pt spacing (was mixed 36/30 with 4/8pt spacing)
- **Tap-outside to blur**: Tapping anywhere in the chat area now resigns keyboard focus (previously only dismissed attachment picker)
- **Top-right toolbar breathing room**: Reduced HStack spacing to 16pt and added 2pt trailing padding on ellipsis for less cramped feel
- **Hidden send button when empty**: Send button now hidden (not just faded) when input is empty; appears with scale+opacity transition when content is typed or file attached
- **File-only send**: Users can attach and send files/images without any text; auto-generates "View the attached file" prompt when sending attachments alone

**Files changed:**

- `apps/ios/Todus/Todus/Features/AI/AIChatView.swift` — All five changes in inputSection, chatInputBox, toolbarContent, sendMessage(), ChatVoiceInputButton

## [2026-03-30] Enhancement — Resizable & movable AI assistant panels

Made both floating and side pane assistant panels user-resizable:

- **Floating panel resizable**: Bottom-right drag handle (min 320×400, max 700×900) with crosshair cursor
- **Floating panel movable**: Header drag gesture moves panel freely around the window
- **Side pane resizable**: Draggable divider replaces static Divider (min 280px, max 600px) with resize cursor
- **Self-managed sizing**: Floating panel manages its own frame via internal `floatingSize` state; MacRootView no longer imposes fixed dimensions
- **Icon consistency**: AssistantButton uses `sparkles` icon matching iOS

**Files changed:**

- `MacAssistantPanel.swift` — Added `floatingSize`, `floatingOffset`, resize handle overlay, `.frame()` and `.offset()` modifiers
- `MacRootView.swift` — Added `sidePaneWidth` state, draggable resize divider with `NSCursor.resizeLeftRight`, removed fixed floating frame

## [2026-03-30] Fix — Clear remaining iOS and macOS build blockers

Resolved the latest Xcode compile errors in both native targets:

- marked the shared AI card date formatter as `nonisolated(unsafe)` so `ISO8601DateFormatter` stops tripping Swift 6 sendability checks
- fixed the voice input controller by storing its completion handler on the main actor and treating `AudioPlayerManager` as the failable optional it is
- removed the `selection` shadowing bug in the macOS root view so the home view can navigate the sidebar state correctly
- verified both targets build successfully with `xcodebuild` for the iOS simulator and macOS

**Files changed:**

- `apps/ios/Todus/Todus/Features/AI/CardViews.swift`
- `apps/ios/Todus/Todus/Features/Voice/VoiceChatViewModel.swift`
- `apps/ios/Todus/Todus/Features/Voice/VoiceInputButton.swift`
- `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`
- `apps/macos/TodusMac/App/MacRootView.swift`
- `apps/ios/Todus/status_ios.md`
- `apps/ios/Todus/status_macos.md`

## [2026-03-30] Enhancement — macOS AI Assistant visual parity with iOS

Second pass to match the iOS AIChatView pixel-for-pixel. Key additions:

- **Page context chip**: Blue pill (e.g. "🏠 Home ×") showing current view, removable by user
- **Context-aware suggestions**: Suggestion pools change per active page (Home/Tasks/Email/Calendar) matching iOS
- **Show more / Show less**: Expandable suggestions with shuffle-on-refresh, matching iOS behavior
- **Prompt library**: Popover with 12 categorized prompt templates (Writing, Planning, Email, etc.)
- **Voice input (mic)**: Full speech-to-text via macOS Speech framework + AVAudioEngine, matching iOS VoiceInputButton
- **Attachment button (+)**: File picker for attaching documents, with removable pill previews
- **Thumbs up/down feedback**: Added to action row matching iOS
- **Animated sparkle icon**: Rotating gradient sparkles icon matching iOS AnimatedSparkleIcon
- **Reasoning box**: Collapsible thinking box with auto-expand/collapse matching iOS ReasoningBox
- **Darker background**: Panel background now matches iOS dark theme
- **Rounded input box**: Input section wrapped in rounded surface card matching iOS chatInputBox design
- **Draft persistence**: Input text saved/restored via UserDefaults
- **Rename conversation**: Alert dialog for renaming chat title
- **Microphone permissions**: Added NSMicrophoneUsageDescription + NSSpeechRecognitionUsageDescription to Info.plist
- **Wider panel**: Floating 400×560 (was 380×520), side pane 380 (was 360) for more breathing room

**Files changed:**

- `MacAssistantPanel.swift` — Complete rewrite with ~900 lines of iOS-parity UI
- `MacRootView.swift` — Passes `selection` to panel for page context chip
- `Info.plist` — Added microphone and speech recognition usage descriptions

## [2026-03-30] Feature — macOS AI Assistant with full iOS feature parity

Complete rewrite of the macOS AI assistant to achieve 100% feature parity with the iOS app. Replaced the placeholder `.sheet()` modal with an inline chat panel supporting two display modes.

### Display Modes

- **Floating mode**: draggable overlay window (380×520) anchored bottom-right, stays open while navigating
- **Side pane mode**: docked 360px panel on the right edge, integrated into the main layout
- Toggle between modes via header button; ⌘L toggles open/close; FAB hides when panel is open

### Streaming & Tool Calls (iOS parity)

- Full SSE streaming with 40ms token batching for smooth typewriter animation
- Tool call processing: `create_task`, `update_task`, `delete_task`, `create_calendar_event`, `send_email`
- Task CRUD mutations applied directly to SwiftData via ModelContext
- Calendar events created via CalendarService actor
- Email sending via EmailService

### Web Search & Reasoning

- `search_status` SSE events show animated search indicator with rotating status text
- `sources` SSE events rendered as clickable source chips (opens URL in browser)
- `reasoning` / `reasoning_done` events displayed in collapsible disclosure group

### Conversation History

- Full conversation persistence to UserDefaults (50-conversation cap)
- History popover for browsing and resuming past conversations
- New conversation button, auto-save on panel hide

### UI Polish

- Inline-only markdown during streaming for performance, full CommonMark after streaming ends
- Action row per message: retry (removes dependent turns) + copy with checkmark feedback
- Model picker (gpt-4.1, o4-mini, gpt-4.1-mini) in header
- Mutation chips with color-coded action badges (green=create, blue=update, red=delete)
- Suggestion chips for empty state quick prompts

**Files created:**

- `apps/macos/TodusMac/Services/AI/MacAIChatService.swift` — full AI chat service with SSE, tool calls, history, retry
- `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift` — polished chat panel with dual display modes

**Files changed:**

- `apps/macos/TodusMac/App/MacAppServices.swift` — added `aiChatService` with calendarService dependency
- `apps/macos/TodusMac/App/MacRootView.swift` — replaced `.sheet()` with inline floating/sidepane panel
- `apps/macos/TodusMac.xcodeproj/project.pbxproj` — registered new files and groups

## [2026-03-30] Fix — Harden iOS AI chat history replay and UI-spec rendering

Resolved three correctness issues in the native iOS AI chat flow that surfaced during code review.

- saved AI conversations now persist mention references alongside message text, so reopened chats keep task/thread/event IDs available for follow-up turns
- retrying an older assistant response now removes later dependent turns before replaying, preventing contradictory branched history from being sent back to the backend
- assistant replies that only contain a `ui-spec` block now clear the raw fenced JSON from the visible message body and render only the generated UI

**Files changed:**

- `apps/ios/Todus/Todus/Domain/AIChatConversation.swift`
- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`
- `apps/ios/Todus/Todus/Features/AI/AIChatMessage.swift`
- `apps/ios/Todus/TASK.md`
- `apps/ios/Todus/plan.md`

## [2026-03-30] Fix — Stabilize iOS AI chat history loading, duplication, and spec-only actions

Resolved a second set of AI chat state issues found during follow-up review.

- loading a saved chat now cancels any active AI stream first, so the newly loaded conversation does not inherit stale streaming/error state from the previous request
- duplicating a conversation now preserves the full in-memory message models, including mentions and assistant metadata, and leaves the duplicate marked unsaved so it can autosave normally
- assistant action rows now remain visible for spec-only replies that render native UI cards, while the copy action is disabled when there is no plain text payload to copy

**Files changed:**

- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`
- `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`
- `apps/ios/Todus/TASK.md`
- `apps/ios/Todus/plan.md`

## [2026-03-30] Fix — Restore iOS AI chat endpoint and message actions

Resolved the current native iOS AI chat regression where every prompt failed immediately with `⚠️ Server error (404).`

- updated the iOS AI chat and notification digest clients to call `/api/ai/chat`, matching the backend router mount
- added targeted assistant-message retry so retry replaces the tapped reply in place instead of appending a duplicate turn
- stabilized the assistant action row so the copy button always uses primary text color and keeps a fixed width while swapping between copy and checkmark states
- preserved existing streaming, search, reasoning, and tool-call handling in the AI chat service

**Files changed:**

- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`
- `apps/ios/Todus/Todus/Services/Notifications/NotificationDigestService.swift`
- `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`
- `apps/ios/Todus/TASK.md`
- `apps/ios/Todus/plan.md`

## [2026-03-29] Fix — Restore iOS AI spec rendering and calendar build

Resolved the current Xcode build failures in the native iOS app:

- replaced the recursive `some View` renderer in `ChatUISpecView` with `AnyView`-based recursion so SwiftUI type inference no longer feeds itself
- marked `EKWrapper` as `@unchecked Sendable` to satisfy Swift 6 concurrency checking when calendar event wrappers move from the background EventKit fetch back to the main thread
- verified the project builds successfully with `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' build`

**Files changed:**

- `apps/ios/Todus/Todus/Features/AI/ChatUISpecView.swift`
- `apps/ios/Todus/Todus/Features/Calendar/EKWrapper.swift`
- `apps/ios/Todus/status_ios.md`
- `apps/ios/Todus/TASK.md`

## [2026-03-29] Feature — Native macOS shell scaffold replaces Electron wrapper

### Summary

Replaced the legacy Electron-based `apps/macos` wrapper with a standalone SwiftUI macOS app scaffold driven by XcodeGen.

This first native macOS pass is intentionally shell-only:

- added a single-window `TodusMac` app
- added `NavigationSplitView` shell layout with a custom sidebar
- added placeholder panes for Home, Tasks, Email, and Calendar
- added a SwiftUI content header with notification, menu, edit, and search affordances
- added a floating Assistant button with a placeholder sheet
- added placeholder account menu and Settings modal
- updated canonical docs to describe macOS as a native SwiftUI target
- updated macOS status tracking to reflect shell completion and the remaining Xcode license blocker for CLI build verification

**Files changed:**

- `apps/macos/README.md`
- `apps/macos/project.yml`
- `apps/macos/TodusMac/App/TodusMacApp.swift`
- `apps/macos/TodusMac/App/MacRootView.swift`
- `apps/macos/TodusMac/App/MacSidebarView.swift`
- `apps/macos/TodusMac/App/MacContentHeaderView.swift`
- `apps/macos/TodusMac/App/AssistantButton.swift`
- `apps/macos/TodusMac/Resources/Info.plist`
- `AGENTS.md`
- `APPS_ARCHITECTURE.md`
- `docs/architecture/README.md`
- `docs/architecture/APPS_ARCHITECTURE.md`
- `docs/development/SCRIPTS_GUIDE.md`
- `docs/testflight-checklist.md`
- `docs/guides/AGENTS.md`
- `apps/ios/Todus/status_macos.md`

## [2026-03-29] Fix — Restore GenerativeUI files to Xcode build sources

ChatUISpec.swift, ChatUISpecView.swift, and CardViews.swift were removed from the Xcode project (PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase) during prior cleanup of the GenerativeUI subdirectory, but the files still exist at Features/AI/ and are actively referenced by AIChatMessage.swift, AIChatView.swift, and AIChatService.swift. Re-added all three files to the project to fix "Cannot find type" build errors.

**Files changed:** `apps/ios/Todus/Todus.xcodeproj/project.pbxproj`

## [2026-03-29] Fix — iOS Xcode build environment reset for CalendarKit registration hangs

### Summary

Investigated repeated Xcode GUI hangs around:

- `RegisterExecutionPolicyException ... CalendarKit.o`
- `RegisterExecutionPolicyException ... CalendarKit_CalendarKit.bundle`

This was not caused by CalendarKit source code itself. The package is a simple SwiftPM dependency with no nested package dependencies or binary artifacts. A clean rebuild showed the hang correlated with local Xcode/macOS environment state after manual cache cleanup.

**Root cause found:**

- Xcode had been configured to use custom build output paths:
  - `~/XcodeDerivedData/Todus`
  - `~/Desktop/Build/Intermediates.noindex`
- After caches were manually deleted, those non-default locations interacted badly with execution-policy registration (`syspolicyd`) and later with a corrupted `XCBuildData/build.db`.

**Fixes applied:**

- Reset Xcode build location preferences back to default DerivedData behavior
- Cleared Todus DerivedData and SwiftPM caches
- Re-resolved package dependencies so CalendarKit was checked out fresh
- Regenerated `apps/ios/Todus/Todus.xcodeproj` from `apps/ios/Todus/project.yml`
- Excluded `**/archived/**` from the iOS target so clean builds do not pull in stale duplicate files like `Navigation/archived/CustomTabBar.swift`

**What this proved:**

- `RegisterExecutionPolicyException` for CalendarKit now completes in a clean isolated build path
- The remaining failures after the reset were ordinary project/source issues surfaced by a true clean build, not CalendarKit registration hangs

**Files changed:**

- `apps/ios/Todus/project.yml`
- `apps/ios/Todus/Todus.xcodeproj/project.pbxproj`
- `apps/ios/Todus/status_ios.md`

## [2026-03-29] Cross-platform code quality fixes — iOS, web, gitignore

### Summary

Batch of code quality fixes across iOS and web apps:

- **`.gitignore`**: Added `.deriveddata/` and `DerivedData/` to prevent Xcode build artifacts from being committed
- **`Info.plist`**: Added standard bundle identification keys (CFBundleIdentifier, CFBundleVersion, etc.) using build setting variables
- **`project.pbxproj`**: Removed stale build references for deleted files (CardViews.swift, ChatUISpec.swift, ChatUISpecView.swift)
- **`GmailOnboardingView`**: Updated copy to include explicit permission disclosure ("Grant access to...")
- **`EmailInboxView`**: Fixed misleading empty state text — replaced "Pull down to refresh" with "Tap Refresh" since pull-to-refresh is only on the thread list
- **`SettingsView`**: Updated Email & AI section footer to describe all controls in the section
- **`MainTabView`**: Added `.snappy` animation to requestCreateSheet handler to match tab bar behavior
- **`AuthService`**: Reset `isSessionExpired` in `signOut()` to prevent stale banner after sign-out
- **`en.json`**: Added `common.actions.unsavedChanges` i18n key
- **`general/page.tsx`**: Replaced hardcoded "Unsaved changes" with i18n call
- **`mail.tsx`**: Added `aria-label="Compose email"` to floating compose button for screen reader accessibility
- **`signatures/page.tsx`**: Replaced hardcoded title/description with i18n message calls

**Files changed:**

- `.gitignore`
- `apps/ios/Todus/Todus.xcodeproj/Info.plist`
- `apps/ios/Todus/Todus.xcodeproj/project.pbxproj`
- `apps/ios/Todus/Todus/App/GmailOnboardingView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`
- `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/Services/Auth/AuthService.swift`
- `apps/mail/messages/en.json`
- `apps/mail/app/(routes)/settings/general/page.tsx`
- `apps/mail/components/mail/mail.tsx`
- `apps/mail/app/(routes)/settings/signatures/page.tsx`

---

## [2026-03-29] iOS UX Fixes — Auth links, onboarding copy, action grouping, create sheet, search indicator, empty states, send error, session confirm, AI detent, settings regrouping

### Summary

Batch of iOS UX improvements across 9 files:

- **I13 AuthView**: Terms of Service and Privacy Policy are now tappable links opening todus.app/terms and todus.app/privacy
- **I2 GmailOnboardingView**: Updated copy to be benefit-oriented ("See your inbox, reply to emails...")
- **I3 EmailThreadView**: Added visual divider between non-destructive (star, unread) and destructive (archive, trash) action buttons
- **I5 HomeView + AppServices + MainTabView**: Events and Tasks "+" buttons now open CreateSheet directly instead of navigating to another tab
- **I8 EmailInboxView**: Added inline "Searching..." indicator when search is in progress
- **I11 EmailInboxView**: Improved empty state with refresh button and better copy
- **I10 EmailComposeView**: Added error alert when email send fails
- **I12 MainTabView**: Session expired banner now shows confirmation dialog before signing out
- **I15 MainTabView**: AI chat sheet uses .medium detent instead of .fraction(0.5)
- **I9 SettingsView**: Merged 9 sections into 4 logical groups (Preferences, Email & AI, Notifications & Privacy, About)

**Files changed:**

- `apps/ios/Todus/Todus/Features/Auth/AuthView.swift`
- `apps/ios/Todus/Todus/App/GmailOnboardingView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift`
- `apps/ios/Todus/Todus/Features/Home/HomeView.swift`
- `apps/ios/Todus/Todus/App/AppServices.swift`
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailComposeView.swift`
- `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`

## [2026-03-29] Fix — Buffer early WebSocket messages in voice proxy

### Summary

In the `/ai/voice-ws` WebSocket proxy, `serverWs.accept()` was called before the upstream Gemini connection was established and forwarding handlers attached. Any client messages arriving during the Gemini `fetch()` would be silently dropped (e.g. the setup config message). Added an early-buffering message handler that queues messages until upstream is ready, then flushes them in order before switching to direct forwarding.

**Files changed:**

- `apps/server/src/routes/ai.ts` — Attach buffering handler immediately after `serverWs.accept()`, flush + switch to direct forwarding after `upstream.accept()`

## [2026-03-29] Fix — Persist Mention IDs Across Follow-up Chat Turns

### Summary

Mentions (e.g. `@thread X`, `@task Y`) only resolved for the turn they were inserted in. The underlying entity IDs were stored in a transient `currentTurnMentions` array that was cleared after each stream, while prior messages were serialized as plain text. A multi-turn flow like "summarize @thread X" → "reply to it" would lose the resolved thread ID on the second turn.

**Fix:** Added a `mentions: [RichInputMentionRef]` property to `AIChatMessage` so each user message persists its mention refs. `buildPayload` now collects de-duplicated mentions from ALL user messages in the conversation history (not just the current turn), ensuring entity IDs remain resolvable across follow-up turns.

**Files changed:**

- `apps/ios/Todus/Todus/Features/AI/AIChatMessage.swift` — Added `mentions` property and init parameter
- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift` — Store mentions on user message at send time; `buildPayload` collects mentions from all user messages with de-duplication

## [2026-03-29] Security Fix — Voice Chat API Key No Longer Sent to Clients

### Summary

The `POST /ai/voice-token` endpoint returned the raw `GOOGLE_GENERATIVE_AI_API_KEY` to any authenticated user. This was a credential leak — users could extract the long-lived key and call Gemini directly outside the app. The `expiresAt` field was just a client-side hint with no server enforcement.

**Fix:** Replaced the REST token endpoint with a **WebSocket proxy** (`GET /ai/voice-ws`). The backend now accepts a WebSocket upgrade from the iOS client (authenticated via the existing Bearer token), opens a separate WebSocket to Gemini with the API key server-side, and transparently forwards all messages bidirectionally. The API key never reaches the client.

**Files changed:**

- `apps/server/src/routes/ai.ts` — Replaced `POST /voice-token` with `GET /voice-ws` WebSocket proxy
- `apps/ios/Todus/Todus/Services/Voice/VoiceProvider.swift` — Protocol: `connect(token:config:)` → `connect(endpoint:authToken:config:)`
- `apps/ios/Todus/Todus/Services/Voice/GeminiLiveProvider.swift` — Connects to backend proxy URL with Authorization header instead of Gemini directly
- `apps/ios/Todus/Todus/Services/Voice/VoiceTokenService.swift` — Rewritten to build WS proxy URL from backend URL + auth token (no longer fetches API key)
- `apps/ios/Todus/Todus/Features/Voice/VoiceChatViewModel.swift` — Updated connect flow to use new `getEndpoint()` API
- `apps/ios/Todus/Todus/App/AppServices.swift` — Updated VoiceTokenService init to take `authService` + `backendURL` instead of `apiClient`

## [2026-03-29] Voice Chat Bug Fixes — Double Disconnect, Data Race, Robustness

### Summary

Fixed two critical bugs and multiple robustness issues in the Live Voice Chat feature:

**Bug 1 — Double disconnect duplicates chat messages:** Both Close/End Call buttons called `disconnect()` then `dismiss()`, triggering `onDisappear` which called `disconnect()` again. Without an early-return guard, `finalizedTurns` was iterated twice, duplicating all voice messages in chat history. Fix: added `guard connectionState != .disconnected` at top of `disconnect()` and clear `finalizedTurns` after writing.

**Bug 2 — Data race on `isMicMuted`:** The `@MainActor`-isolated `isMicMuted` was read from the audio processing thread in the `installTap` callback and the DispatchSource timer. Fix: added a lock-protected `_micMutedAtomic` Bool that audio threads read, synced from `toggleMute()`.

**Additional fixes:**

- Simplified redundant `connect()` guard that only matched `.failed("")` instead of any `.failed` case
- Provider is now disconnected if audio capture setup fails after a successful connection
- `sendText()` now checks connection state before sending
- Tool call status tracking prevents concurrent tool calls from clobbering each other's UI status
- `sendToolResponse` errors are now logged instead of silently swallowed
- AVAudioConverter input block correctly returns `.noDataNow` after first data supply
- AudioPlayerManager: force-unwrap replaced with guard-let + fatalError; `isPlaying` getter synchronized on audioQueue; playback state resets when scheduled buffers complete naturally
- GeminiLiveProvider: event stream recreated on `connect()` (no longer single-use); URLSession stored and invalidated on disconnect; send functions throw `.notConnected` instead of silent return; receive loop error handler cleans up WebSocket state; `goAway` emits `.disconnected` (no auto-reconnect exists); `sendJSON` throws on nil webSocketTask; setup failure cleans up connection
- Voice tool calls now respect `aiCanWriteTasks` permission (matches text chat path)
- Tool result JSON built with `JSONEncoder` instead of string interpolation (prevents breakage from special characters in task titles)
- Calendar event creation errors propagated instead of silently swallowed
- `shouldSearchWeb()` evaluates time-sensitive keywords before short-command check (so "weather today" triggers search)
- Added `:focus-visible` keyboard focus styles for `.editor-suggestion-item` (WCAG 2.1 AA accessibility)

### Updated Files

- `apps/ios/Todus/Todus/Features/Voice/VoiceChatViewModel.swift` — disconnect guard, clear finalizedTurns, thread-safe mic flag, connect guard simplification, audio capture failure cleanup, sendText connection check, tool call tracking, converter fix
- `apps/ios/Todus/Todus/Services/Voice/AudioPlayerManager.swift` — safe init, synchronized isPlaying, buffer completion tracking
- `apps/ios/Todus/Todus/Services/Voice/GeminiLiveProvider.swift` — reusable event stream, URLSession lifecycle, throw on not-connected, receive loop cleanup, goAway state fix, sendJSON guard
- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift` — aiCanWriteTasks check, encodeToolResult helper, calendar error handling
- `apps/server/src/routes/ai.ts` — shouldSearchWeb ordering fix
- `apps/mail/components/create/prosemirror.css` — focus-visible keyboard accessibility

### Skipped (verified not real bugs)

- VoiceTokenService race condition: class is `@MainActor`, so calls are serialized by the actor executor
- Raw API key in `/ai/voice-token`: Gemini Live requires direct client WebSocket — no way to proxy bidirectionally without a full relay server

## [2026-03-28] iOS compose mention follow-up fixes

### Summary

Reviewed the current iOS mention/slash-command compose changes and fixed two issues that were still present in the live code: email compose body focus was no longer wired to the existing `focusedField` state, and person mention suggestions could surface a different top-10 subset between runs because they were truncated before applying a stable sort.

### Updated Files

- `apps/ios/Todus/Todus/Features/Email/EmailComposeView.swift` — restored body-editor focus by passing explicit focus state into `RichComposerInput`, and sorted grouped senders by a stable name/email key before `prefix(10)`.
- `apps/ios/Todus/Todus/Features/Tasks/CaptureComposer.swift` — added optional focus control to `RichComposerInput` / `PasteHandlingTextInput` while preserving default auto-focus behavior for other existing callers.

### User-facing impact

- Opening compose now correctly places the keyboard in the body when `To` and `Subject` are already populated.
- Person mention suggestions in compose now remain stable and predictable across launches and rebuilds.

## [2026-03-28] Live Voice Chat — Gemini Live API Integration

### Summary

Production-quality bidirectional voice chat with AI assistant using Gemini Live API. Provider-agnostic architecture (protocol abstraction for future OpenAI Realtime support). No API keys in the iOS binary — backend mints short-lived tokens. Full tool call support (create tasks, send emails, create calendar events) during voice sessions.

### Backend (`apps/server/src/routes/ai.ts`)

- Added `POST /ai/voice-token` endpoint: returns `GOOGLE_GENERATIVE_AI_API_KEY` with 5-minute TTL and model name, gated by Bearer auth

### iOS — New Files

- `Services/Voice/VoiceProvider.swift` — Protocol + enums (`VoiceConnectionState`, `TranscriptRole`, `VoiceSessionEvent`) + `VoiceSessionConfig` struct
- `Services/Voice/GeminiLiveProvider.swift` — WebSocket implementation using native `URLSessionWebSocketTask`, handles Gemini Live bidirectional protocol
- `Services/Voice/VoiceTokenService.swift` — Fetches and caches tokens from backend
- `Services/Voice/AudioPlayerManager.swift` — Plays PCM16 24kHz audio chunks via `AVAudioEngine` + `AVAudioPlayerNode`
- `Features/Voice/VoiceChatViewModel.swift` — @Observable ViewModel: manages provider, audio capture (PCM16 16kHz), transcript state, tool call routing
- `Features/Voice/VoiceChatModalView.swift` — Full-screen modal: transcript area, animated listening/speaking indicator, mic mute/end call controls

### iOS — Modified Files

- `AIChatService.swift` — Added `appendVoiceExchange()`, `buildSystemPromptForVoice()`, `processVoiceToolCall()`, `voiceToolDeclarations()`
- `AIChatMessage.swift` — Added `MessageSource` enum (.text/.voice) with `source` property
- `AIChatView.swift` — Added waveform button (AI gradient) in both expanded/compact chat input modes + `.fullScreenCover` for voice modal
- `AppServices.swift` — Added `VoiceTokenService` registration

### Architecture Notes

- Voice transcripts stay local in the modal; only finalized exchanges are written to main chat history on disconnect
- Tool calls route through existing `AIChatService` pipeline
- Audio: capture PCM16 @ 16kHz via AVAudioEngine → 100ms chunks → WebSocket; playback PCM16 @ 24kHz

---

## [2026-03-28] Web Search + Inline Citations + Reasoning UI in AI Chat

### Summary

Full ChatGPT/Perplexity-style search + reasoning UX in the AI chat. When a user asks a factual question, the backend searches the web via Perplexity, streams sources as custom SSE events, and the iOS app renders a "Searching the web…" indicator, source pills, tappable citation superscripts, and a collapsible reasoning box. Reasoning models (deepseek-r1, o1, etc.) get a dedicated thinking UI with auto-collapse.

### Backend (`apps/server/src/routes/ai.ts`)

- Added `shouldSearchWeb()` heuristic to detect queries needing web information
- Added `performWebSearch()` — Tavily primary (pure search API, 1k free/mo, real snippets), Perplexity sonar fallback (no SDK needed — raw `fetch` for both). Gracefully returns empty if neither key is configured.
- Added `injectSearchContext()` to format sources + citation instructions into the LLM prompt
- Modified `/ai/chat` SSE stream to write custom events (`search_status`, `sources`) before piping OpenRouter response
- Refactored response stream from TransformStream passthrough to ReadableStream with explicit writer (supports pre-stream custom events while preserving Mem0 capture)
- Added `TAVILY_API_KEY` to `env.ts` type definitions

### iOS Model (`AIChatMessage.swift`)

- Added `WebSource` struct (url, title, snippet, domain computed property)
- Extended `AIChatMessage` with: `sources`, `searchQueries`, `searchState` (SearchPhase enum), `reasoningContent`, `reasoningDurationMs`

### iOS Service (`AIChatService.swift`)

- Added `SSECustomEvent` and `SSESourcePayload` decode structs
- Modified SSE parsing loop to try custom event decode before OpenRouter chunk decode (backward compatible)
- Added `handleCustomEvent()` method to update message search/source/reasoning state

### iOS UI (`AIChatView.swift`)

- Added `SearchingIndicator` view: spinning globe + "Searching the web…" + query text
- Added `SourceChipsView`: horizontal ScrollView of capsule pills with favicon + domain, tappable to open URL
- Modified `assistantBubble` to render search indicator and source chips above the answer content
- Added scroll-to-bottom trigger when sources arrive

### V2 Additions (same session)

**Backend:**

- Improved `shouldSearchWeb()` heuristic: skips task/email/calendar commands, filters short messages, two-tier check (time-sensitive vs factual questions vs own-data queries)
- Added reasoning token extraction from OpenRouter SSE (`delta.reasoning_content` / `delta.reasoning`) for reasoning models (deepseek-r1, o1, o3-mini)
- Re-emits reasoning tokens as custom `reasoning` events + `reasoning_done` with duration

**iOS UI:**

- `ReasoningBox`: collapsible thinking/reasoning box with pulsing brain icon, auto-expands while streaming, auto-collapses 0.8s after completion, tap header to toggle, shows "Thought for Xs"
- `SourceDetailSheet`: tap any source chip to expand a detail sheet with full title, domain, snippet, and "Open in Safari" button. Long-press for context menu (open in Safari, copy URL)
- Source chips now show citation number badges `[1]`, `[2]` alongside favicon + domain
- `styleCitations()`: post-processes AttributedString to highlight `[n]` patterns as blue superscript text, linked to source URLs (works in both inline streaming and full markdown modes)
- Citation links open directly in Safari when tapped

### Architecture Decision

- Single SSE stream with custom event types (backward compatible — old clients silently skip unknown JSON)
- Backend-orchestrated search (client doesn't need to know about search providers)
- Smart heuristic search trigger with command filtering (skips task/email/calendar ops)

## [2026-03-28] Comprehensive SEO Overhaul — From Zero to Indexed

### Summary

todus.app had zero Google-indexed pages. This overhaul adds all missing SEO infrastructure, creates competitor comparison pages and a blog for organic traffic, and enables pre-rendering so Google sees real HTML content.

### New Files

- `apps/mail/public/robots.txt` — Crawler directives (allow public, disallow /mail/, /settings/)
- `apps/mail/public/sitemap.xml` — All public URLs for search engine discovery
- `apps/mail/app/(full-width)/compare/[competitor]/page.tsx` — Data-driven comparison pages (vs Superhuman, Shortwave, Spark, Motion)
- `apps/mail/app/(full-width)/blog/index.tsx` — Blog index page
- `apps/mail/app/(full-width)/blog/[slug]/page.tsx` — Blog post pages with 3 initial SEO articles
- `SEO-AUDIT.md` — Full audit findings, implementation status, and content calendar

### Updated Files

- `apps/mail/lib/site-config.ts` — New title, description, Twitter cards, JSON-LD schemas (Organization, SoftwareApplication, FAQPage), 25+ target keywords
- `apps/mail/app/root.tsx` — Canonical URL, Twitter cards, keywords meta, robots meta, JSON-LD structured data, apple-touch-icon, preconnect/dns-prefetch
- `apps/mail/react-router.config.ts` — Pre-render 16 public pages for SEO (static HTML at build time)
- `apps/mail/app/routes.ts` — Added /compare/:competitor, /blog, /blog/:slug routes
- `apps/mail/app/(full-width)/about.tsx` — Page-specific SEO meta tags
- `apps/mail/app/(full-width)/pricing.tsx` — Page-specific SEO meta tags

### SEO Elements Added

- Title tag: "Todus — AI Email, Calendar & Tasks in One App"
- Meta description with value prop and YC credibility
- 25+ target keywords in meta tag
- Canonical URL on every page
- Open Graph tags (title, desc, image, dimensions, alt, site_name)
- Twitter/X Cards (summary_large_image)
- JSON-LD Organization schema
- JSON-LD SoftwareApplication schema
- JSON-LD FAQPage schema with 6 Q&As
- robots.txt with crawler directives
- sitemap.xml with all public URLs
- Pre-rendered HTML for all 16 public pages

### Verification

- Build succeeds: `pnpm --filter mail build` completes with all 16 pages pre-rendered
- Pre-rendered HTML verified to contain all meta tags, structured data, and visible content

---

## [2026-03-28] Cross-platform mentions and slash commands

### New Features

- **Shared mention model**: Added shared `MentionKind` / `MentionRef` types in `packages/shared` so web, server, and iOS use the same structured mention payload.
- **Server mention search**: Added `mentions.search` tRPC route for task, thread, and person lookup with grouped results and stable IDs. Event mentions remain feature-gated on web until a web provider exists.
- **AI mention context**: `/ai/chat` and the web agent route now accept optional `mentions` arrays and inject compact structured mention context into the current user turn before model execution.
- **Web TipTap mentions and slash commands**: The active shared editor hook now supports `@` mentions, `/` commands, human-readable mention chips, and per-surface command ordering for email compose and AI chat.
- **Web submit serialization**: Email compose now strips mention metadata to readable text before send; AI chat extracts mention refs separately and submits them as structured context.
- **iOS rich input**: Added a reusable `UITextView`-backed rich composer input with shared slash command definitions, inline mention highlighting, and reuse across task capture, email compose, and AI chat.
- **iOS mention-aware AI requests**: Native AI chat now collects mention refs and includes them in the backend payload alongside the visible user message.

### Architectural Notes

- **Shared slash semantics**: iOS task capture now derives slash actions from the same shared command model used by the new rich input surfaces instead of maintaining a one-off command list.
- **Compose signature command**: Email compose now supports `/signature` using the currently active native signature.

### Verification

- `pnpm --filter @zero/mail exec tsc --noEmit --pretty false` narrowed to the edited mail files reports no errors.
- `pnpm --filter @zero/server exec tsc --noEmit --pretty false` narrowed to the edited server files reports one pre-existing unrelated overload error in `apps/server/src/routes/agent/index.ts`.
- `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -configuration Debug -sdk iphonesimulator -derivedDataPath /tmp/todus-codex-derived-data build CODE_SIGNING_ALLOWED=NO` was started to validate the edited Swift files in an isolated build directory.

## [2026-03-27] iOS — Single `NotificationService`, action IDs aligned with `TodosApp`

### Bug Fix / Architecture

- **Removed duplicate `NotificationService`**: Only `Services/Notifications/NotificationService.swift` is compiled now; the old `Resources/NotificationService.swift` copy (different `Action` string constants) is deleted. Xcode file reference moved to `Services/Notifications/`. Action identifiers remain `TASK_COMPLETE` / `TASK_SNOOZE`, matching `UNNotificationAction` registration and `AppDelegate` in `TodosApp.swift`.
- **Merged behavior**: 1-hour-before-due scheduling, `TASK_REMINDER` category, async permission request before scheduling (from the former Resources implementation), plus `clearAll` / `cancel(withIdentifiers:)` helpers.

---

## [2026-03-27] iOS — Global search, task search bar visibility, touch targets, UI polish

### New Features

- **Global search sheet**: Magnifying glass button added as first item in `AppTopHeader` action pill. Opens a full-screen sheet (`GlobalSearchView`) that searches tasks (SwiftData), emails (in-memory threads), calendar events, and people — all local, no extra network calls. Tap results to deep-navigate.
- **Touch targets expanded**: Added `minTouchTarget()` extension (`frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())`) and applied to all small buttons across the app — search clear buttons, sort menu, email thread actions, board column controls, AI chat send/stop/config, voice buttons, attachment delete. Skipped dense equal-width rows (view mode picker, tab bar) to avoid conflicts.

### Bug Fixes / Visual Improvements

- **Task search bar visibility**: Changed background from `surfaceSecondary.opacity(0.55)` (nearly invisible) to `surfacePrimary` (full opacity), and border from `cardBorder` to `strongBorder` — clearly visible in both light and dark mode.
- **Avatar resized and made circular**: `AppTopHeader` avatar is now 34×34pt `Circle()` (was 40×40 `RoundedRectangle`), matching the height of the action pill beside it.
- **Calendar header overlap fixed**: `CalendarContainerView` now accepts `topInset: CGFloat` and applies it via `additionalSafeAreaInsets.top` on the `CalendarViewController`, pushing CalendarKit's scroll content below the SwiftUI `AppTopHeader` overlay.

### Files Changed

- `DesignSystem/AppTheme.swift` — minTouchTarget extension, avatar → circle, global search button + sheet in actionsPill
- `Features/Tasks/TasksTabView.swift` — search bar background/border fix + touch targets
- `Features/Search/GlobalSearchView.swift` — **NEW** — full global search sheet
- `Navigation/MainTabView.swift` — calendar header height measurement + topInset wiring
- `Features/Calendar/CalendarContainerView.swift` — `topInset` param + additionalSafeAreaInsets
- Multiple view files — `.minTouchTarget()` applied to small buttons

---

## [2026-03-27] iOS — AI-powered Notification Center

### New Feature

- **Notification Center sheet**: Tapping the bell icon in the app header now opens a notification center sheet (was: opened iOS system notification settings). The sheet shows an AI-generated digest of tasks due, upcoming calendar events, and important unread emails — grouped by type with priority indicators and tap-to-navigate actions.

### Architecture

- **NotificationDigestService** (`Services/Notifications/`): Sends local task/event/email data to `/ai/chat` with a specialized system prompt. Uses non-streaming mode for simpler JSON response parsing.
- **NotificationCenterView** (`Features/Notifications/`): SwiftUI sheet with loading skeleton, error/empty states, and grouped notification cards following existing HomeView design patterns.

### Files Changed

- `AppTheme.swift` — Bell button now opens NotificationCenterView sheet instead of system settings
- `NotificationDigestService.swift` — **NEW** — AI digest backend integration
- `NotificationCenterView.swift` — **NEW** — Notification center sheet UI

---

## [2026-03-27] iOS — Fix Gmail connection persistence + Connect/Permission view consistency

### Bug Fixes

- **Gmail connection not persisting after onboarding**: `GmailOnboardingView` now calls `emailService.checkConnection()` + `loadThreads()` after OAuth, so the email tab reflects the connected state immediately.
- **`hasConnection` default changed from `true` to `false`**: Prevents a brief flash of the thread list before `checkConnection()` runs on first load.

### Visual Consistency

- **EmailConnectView**: Rewritten to match `GmailOnboardingView` exactly — uses `GmailIconView(size: 88)` icon, `AppPrimaryButtonStyle()` button with `GmailIconView(size: 20)` inline, same spacing/typography.
- **CalendarPermissionView**: Rewritten to match onboarding styling — uses `AppleCalendarIconView(size: 88)` instead of generic SF Symbol, `AppPrimaryButtonStyle()` buttons, same layout pattern.

### Files Changed

- `GmailOnboardingView.swift` — Added `checkConnection()` + `loadThreads()` after successful OAuth
- `EmailConnectView.swift` — Full rewrite to match onboarding styling
- `CalendarPermissionView.swift` — Full rewrite to match onboarding styling
- `EmailService.swift` — `hasConnection` default changed from `true` to `false`

---

## [2026-03-27] iOS Tasks — Color System, Scroll Fix, Visual Overhaul

### Bug Fixes

- **Board column scroll**: Columns now have internal vertical `ScrollView` so card overflow scrolls instead of being clipped. Header stays sticky above the scroll area.

### Design Overhaul — All Task Views

- **Consistent tinted status system**: Todo = muted gray, Doing = muted blue, Done = muted green. Applied across board columns, table rows, list tags, and calendar headers.
- **Board columns**: Each column has a very subtle tinted background (0.025 opacity) and tinted border (0.08 opacity). Drop highlight intensifies the tint. Column gap tightened (12→10). Dashed add-task button at bottom.
- **Board cards**: Left-edge color indicator bar per status. Priority flag icons. Overdue dates in red, today in amber. Completed tasks show strikethrough with dimmed text. Thinner border (0.5px).
- **Table view**: Status column now shows colored pills with icon + text (tinted bg + border). Checkbox uses status tint color. Priority dot indicator. Color-coded due dates. Uppercase header labels. "Move to…" context menu added.
- **Calendar view**: Bucket headers now have colored icons (sun for Today, sunrise for Tomorrow, calendar for This Week) with tinted count badges. Each bucket has a unique warm→cool color progression.
- **List view (TaskRowView)**: Status tags now use tinted backgrounds matching their column color. Due date tags are color-coded (red=overdue, amber=today). Priority tags use colored flag icons. All tags use consistent 5pt radius with 0.5px tinted borders. Row corner radius refined (16→14).

### Files Changed

- `BoardView.swift` — Column gap 12→10
- `BoardColumnView.swift` — Vertical scroll for cards, sticky header, tinted column bg/border, dashed add-task button
- `BoardTaskCard.swift` — Left-edge color bar, priority flags, due date coloring, strikethrough for completed
- `TaskTableView.swift` — Colored status pills, priority dots, due date colors, uppercase header, "Move to…" context menu
- `CalendarTaskView.swift` — Colored bucket headers with icons, tinted count badges, warm→cool color progression
- `TaskRowView.swift` — Tinted status/due/priority tags, dimmed completed state, refined tag sizing

## [2026-03-27] iOS Board View — Drag/Drop, Inline Add, UI Polish

### Features

- **Drag & drop tasks between columns**: Drop destination with animated status change and visual drop highlight using column tint colors.
- **Tap column empty area to add task**: Tapping anywhere in a column's empty space opens an inline add field at the top of the card list.
- **+ button in column headers**: Quick-add button in the top-right of each column header, tinted with the column's accent color.
- **"Add task" button at column bottom**: Outlined button with muted column-tint border and text, matching each status's color identity.
- **Context menu "Move to…" submenu**: Board cards now have a status-change submenu in the long-press context menu for quick column moves.
- **`captureInStatus()` method**: New `TaskCaptureService` method for creating tasks directly into a specific status column with full sync.

### UI Polish

- **Column tint colors**: Each `TaskStatus` now has a subtle accent color (slate for Todo, blue for Doing, green for Done) and a status icon.
- **Tighter spacing**: Reduced column width (272→264), card padding (12→10/9), card corner radius (16→10), column corner radius (16→14).
- **Refined typography**: Smaller, denser text (13→12pt cards, 13→12pt headers), tighter tracking, softer foreground opacity.
- **Lighter column backgrounds**: Reduced from solid fill to 55% opacity for a more breathable look.
- **Removed heavy shadows**: Cards use clean border-only styling instead of glassCard with drop shadows.

### Files Changed

- `apps/ios/Todus/Todus/Domain/TaskStatus.swift` — Added `tintColor`, `systemImage` properties
- `apps/ios/Todus/Todus/Services/Tasks/TaskCaptureService.swift` — Added `captureInStatus()` method
- `apps/ios/Todus/Todus/Features/Tasks/BoardColumnView.swift` — Full rewrite with inline add, + button, add-task button, refined styling
- `apps/ios/Todus/Todus/Features/Tasks/BoardTaskCard.swift` — Refined styling, added "Move to…" context menu
- `apps/ios/Todus/Todus/Features/Tasks/BoardView.swift` — Tighter spacing (16→12 gap), removed tap-to-dismiss-keyboard gesture

## [2026-03-27] Mem0 Integration — Persistent AI Memory

### New Feature

- **`apps/server/src/lib/mem0.ts`** (NEW): Mem0 REST API client with multi-layer caching (in-memory → KV → API). Provides `addMemories`, `searchMemories`, `getAllMemories`, `getCachedMemories`, `preloadMemories`, `invalidateMemoryCache`, and `formatMemoriesForPrompt`.
- **`apps/server/src/env.ts`**: Added `MEM0_API_KEY` to `ZeroEnv` type. Set via Cloudflare dashboard secrets.
- **`apps/server/src/routes/ai.ts`**: Integrated Mem0 into `/ai/chat` (iOS flow). Injects cached memories into system prompt. Captures assistant response via TransformStream tee and stores conversation in Mem0 post-stream.
- **`apps/server/src/routes/agent/index.ts`**: Integrated Mem0 into ZeroAgent (web flow). Preloads memories on WebSocket connect (background). Injects cached memories into system prompt (0ms). Stores conversation in Mem0 after response (fire-and-forget).

### Architecture

- **Zero latency**: Memories are preloaded on WebSocket connect / KV-cached. Hot path reads are 0ms (in-memory) or <5ms (KV). No Mem0 API calls block the user.
- **Cross-platform**: Both web and iOS share the same `user_id` (Better Auth user.id), so memories cross-pollinate.
- **Graceful degradation**: All Mem0 calls are try/catch wrapped. If Mem0 is down or unconfigured, AI works normally without memory.
- **No iOS changes needed**: Backend handles all Mem0 integration server-side.

### Setup Required

- Add `MEM0_API_KEY` as a Cloudflare secret (dashboard) and in `.env` for local dev.
- Sign up at https://app.mem0.ai to get an API key.

---

## [2026-03-27] Open source — secret hygiene & CI

### Security (contributor-facing)

- **Audited repo**: No real API keys or OAuth secrets found in tracked source; secrets belong in `.env` / `.dev.vars` / `wrangler secret` (all gitignored or dashboard-only).
- **`apps/server/wrangler.jsonc` (local)**: Removed numeric placeholders for `ELEVENLABS_API_KEY` and `VOICE_SECRET` (empty in `vars`); clarified dev JWT placeholder string. Added comment that real secrets must not live in committed `vars`.
- **`apps/server/src/env.ts`**: `JWT_SECRET` / `ELEVENLABS_API_KEY` typings widened to `string` (no fake literals).
- **`.gitignore`**: Ignore common credential filename patterns (`*credentials*.json`, Google service account blobs, etc.).
- **`SECURITY.md`**: Guidelines for reporting issues, forks, and never committing secrets.
- **`.github/workflows/gitleaks.yml`**: Gitleaks on pull requests.

---

## [2026-03-27] iOS Code Review — View Layer Fixes (Batch 2)

### Bug Fixes & Improvements

- **CalendarViewController.swift**: Added `inFlightDates` Set to prevent duplicate background EventKit fetches for the same day during rapid scrolling.
- **EmailConnectView.swift**: Added `@State isLoading` and `errorMessage`, wrapped Task in do-catch, disabled button while loading.
- **EmailRowView.swift**: Replaced hardcoded `Color.blue` with `AppTheme.accentBlue` for the unread indicator. Added combined accessibility label.
- **BoardView.swift**: Added `taskChangeSignature` computed property to detect status-only changes that `@Query` `onChange(of:)` misses.
- **CustomTabBar.swift** (active): Removed ineffective `.tracking()` modifier from Image views (only works on Text). Removed unused `iconTracking` constant.
- **TaskDetailSheet.swift**: Pass trimmed folder name to `createFolder`. Added `.accessibilityLabel("Create folder")` to the create-folder button.
- **TaskRowView.swift**: Increased checkbox tap target from 36x36 to 44x44pt per Apple HIG (visual icon stays at 18pt).
- **CalendarPermissionView.swift**: Updated Settings path from "Privacy → Calendars" to "Privacy & Security → Calendars".
- **SenderAvatarView.swift**: Changed `.task { urlIndex += 1 }` in failure case to `.onAppear` to prevent re-run loops. Reordered `fetchCandidateURLs` to prioritize backend-resolved URLs over local fallbacks.
- **AIChatView.swift + AIChatService.swift**: Retry button now actually replays the last user message via new `retry()` method instead of just clearing the error.
- **Archived CustomTabBar.swift**: Added accessibility labels to AI/create action buttons and tab buttons. Fixed `glassEffect(in:)` → `glassEffect(.regular, in:)` to match correct iOS 26 API. Removed ineffective `.tracking()` from Image views.

### Files Changed

- `Features/Calendar/CalendarViewController.swift`
- `Features/Calendar/CalendarPermissionView.swift`
- `Features/Email/EmailConnectView.swift`
- `Features/Email/EmailRowView.swift`
- `Features/Email/SenderAvatarView.swift`
- `Features/Tasks/BoardView.swift`
- `Features/Tasks/CustomTabBar.swift`
- `Features/Tasks/TaskDetailSheet.swift`
- `Features/Tasks/TaskRowView.swift`
- `Features/AI/AIChatView.swift`
- `Services/AI/AIChatService.swift`
- `Navigation/archived/CustomTabBar.swift`

---

## [2026-03-27] iOS Code Review Follow-up Fixes

### Bug Fixes & Hardening

- **AppServices.swift**: Persist migrated signatures to UserDefaults after legacy migration (prevents re-migration on every launch). Added logging for JSONEncoder failures in signatures didSet.
- **TodosApp.swift**: Moved `appDelegate.modelContainer` assignment into `initializeApp()` before @State properties are set, eliminating notification race condition. Replaced `try?` with `do/catch` + logging for context.save() and notification scheduling.
- **EmailModels.swift**: Replaced `UUID().uuidString` fallback in EmailAttachment with deterministic ID based on filename+size. Changed date parsing fallback from `Date()` to `Date.distantPast` with logging.
- **TodosAPIClient.swift**: Added missing `EmptyResponse` struct. After successful 401 silent refresh, requests now retry automatically instead of throwing.
- **AuthService.swift**: Converted `userName`/`userImage` from computed to stored properties with Keychain-syncing didSet. Added HTTP status check in `fetchUserProfile()` before parsing JSON.
- **TaskCaptureService.swift**: Reschedules notification when transitioning back to `.todo`. Cancels notification on `.done` in `updateTaskDetails()`. Schedules notification after enrichment applies a parsed due date.
- **NotificationService.swift**: `scheduleTaskReminder` now properly checks/requests authorization before scheduling notifications.

### Files

- `App/AppServices.swift` — signature migration persistence + error logging
- `App/TodosApp.swift` — notification race fix + error logging
- `Domain/EmailModels.swift` — deterministic attachment IDs + date fallback
- `Services/API/TodosAPIClient.swift` — EmptyResponse struct + retry-after-refresh
- `Services/Auth/AuthService.swift` — stored userName/userImage + HTTP status check
- `Services/Tasks/TaskCaptureService.swift` — notification lifecycle consistency
- `Resources/NotificationService.swift` — async authorization check

## [2026-03-27] iOS Settings — Email Signatures sub-page

### Feature: Full Signature Management

- **`SignaturesView`**: List showing all signatures with a checkmark on the active one. "None" row at top to disable signatures. Swipe-to-delete on each row. "+" toolbar button to create new. Each row navigates to the editor.
- **`SignatureEditorView`**: Name field + TextEditor for body + "Use as active signature" toggle + Delete button. Presented as a sheet for new signatures, pushed page for editing.
- **SettingsView**: Replaced the signature toggle + inline textfield with a `NavigationLink` to `SignaturesView`. Shows the active signature name (or "Off") as the row's value hint.
- **AppServices**: `signatures: [EmailSignature]` (JSON-persisted) + `selectedSignatureID: UUID?` + `activeSignature` computed property. Old `signatureEnabled`/`signatureText` properties preserved as backward-compat computed properties. Migration: existing single-text signature is imported as a "Default" signature on first launch with new version.
- **`EmailSignature` model**: `Codable + Identifiable + Sendable` struct in `Domain/EmailModels.swift`.

### Files

- `Domain/EmailModels.swift` — EmailSignature struct
- `App/AppServices.swift` — signatures/selectedSignatureID storage + migration
- `Features/Settings/SignaturesView.swift` — NEW (SignaturesView + SignatureEditorView)
- `Features/Settings/SettingsView.swift` — NavigationLink in email section
- `Todus.xcodeproj/project.pbxproj` — SignaturesView.swift registered

## [2026-03-27] iOS Splash screen redesign + brand icon fixes

### Splash Screen

- **Before**: Plain "Todus" text + spinner — no visual identity.
- **After**: Branded rounded-square app icon mark (checklist SF Symbol, 96pt) + "Todus" title (rounded bold) + spinner below. (`TodosApp.swift`)

### Brand Icon Fixes

- **AppleRemindersLogo clipping**: Previous `rowSpacing = h * 0.27` caused total content (1.14h) to overflow the frame, clipping the orange 3rd row. Reduced to `h * 0.11`; all 3 rows now fit at every size. (`BrandIcons.swift`)
- **AppleRemindersIconView**: Refactored to use `AppIconContainer` (same pattern as GmailIconView) — white rounded-rect background with proper breathing room. No more stretching to fill the frame.
- **AppIconContainer padding**: Inner icon frame reduced from `size * 0.72` to `size * 0.62` — ~19% padding on each side so icons feel airy.

### Files

- `apps/ios/Todus/Todus/App/TodosApp.swift` — branded splash
- `apps/ios/Todus/Todus/DesignSystem/BrandIcons.swift` — spacing fix, padding fix, AppleRemindersIconView refactor

## [2026-03-27] iOS — Fix 9s Startup Black Screen & Runtime Hangs

### Startup Black Screen Fix (CRITICAL)

- **TodosApp**: Deferred `AppServices` and `ModelContainer` initialization from synchronous `init()` to async `.task` context. Shows a branded splash screen immediately while services initialize in the background. Previously all 12+ services + SwiftData schema reconciliation ran synchronously before the first frame, causing a 9+ second black screen.
- **AIChatService**: Deferred `loadPersistedConversations()` (JSON deserialization from UserDefaults) to an async Task instead of running synchronously during init.

### Runtime Hang Fixes (from earlier session)

- Cached expensive computed properties (`buckets`, `tasksDueToday`, `filteredThreads`, `visibleTasks`, `tasksByStatus`) across 5 views to prevent recalculation on every body evaluation.
- Parallelized startup operations in RootView (auth upgrade + reminders setup).
- Fixed settings sheet binding with proper `@Bindable` pattern.
- Batched email thread fetches from 30 simultaneous to groups of 8.
- Fixed `EmailMessage`/`EmailAttachment` `Codable` → `Decodable`, added `Equatable` to `EmailThread`.

## [2026-03-27] iOS — Swift 6 concurrency build fixes (Todus)

### Fixed (Xcode / Swift 6)

- **`TodosApp.swift`**: Removed ineffective `@preconcurrency` on `UNUserNotificationCenterDelegate`. Snooze handling now uses a `Sendable` `SnoozeContentSnapshot` and rebuilds `userInfo` as `["taskID": taskIDString]` on the main actor (avoids sending `UNNotificationContent` / non-Sendable dictionaries across isolation).
- **`CalendarViewController.swift`**: EventKit access completions use a `@Sendable` closure that only schedules `Task { @MainActor [weak self] in ... }`, fixing `EKEventStoreRequestAccessCompletionHandler` data-race diagnostics.
- **`SenderAvatarView.swift`**: Initials avatar background color no longer uses `String.hashValue` (unstable across launches). Uses the same deterministic UTF-16 / JS `<<` algorithm as web `getAvatarColorIndex` in `bimi-avatar.tsx`.
- **`Services/Notifications/NotificationService.swift`**: Snooze now schedules via `enqueueTaskReminder(fireDate:)` at `now + 1h` instead of a synthetic `dueDate` passed through `scheduleTaskReminder` (avoids confusing stacked offsets; behavior unchanged).

### Files

- `apps/ios/Todus/Todus/App/TodosApp.swift`
- `apps/ios/Todus/Todus/Features/Calendar/CalendarViewController.swift`
- `apps/ios/Todus/Todus/Features/Email/SenderAvatarView.swift`
- `apps/ios/Todus/Todus/Services/Notifications/NotificationService.swift`

---

## [2026-03-27] PRD rewrite + iOS feature implementation (Phases 1–6)

### Documentation

- **PRD.md rewritten** as pure product spec — removed all architecture/code, added User Flows, Empty & Error States, Notifications, AI Interaction Model, Settings Screen Spec, Database Schema Revisions sections
- **AGENTS.md rewritten** from scratch — agent-agnostic architecture reference for all AI coding agents (Claude, Cursor, Gemini, etc.)
- **CLAUDE.md updated** — added iOS app detail (services layer, auth flows, data layer), fixed auth providers list
- **APPS_ARCHITECTURE.md updated** — fixed stale Expo/React Native and Next.js references

### iOS: Phase 1 — Empty & Error States

- New `CalendarPermissionView.swift` — shown when calendar access is denied/not-determined
- New `NetworkMonitor.swift` — NWPathMonitor wrapper with offline banner in MainTabView
- `AIChatView` — added AI unreachable error state with retry button
- `HomeView` — composite "Get Started" card when all sections empty

### iOS: Phase 2 — Settings Screen Completion

- **Delete account** — double confirmation (dialog → type "DELETE" alert), backend call + local wipe
- **Disconnect Gmail** — confirmation dialog, calls `connections.delete` tRPC
- **AI tone picker** — Professional/Casual/Concise preference injected into system prompt
- **Notification toggles** — in-app Task Due Reminders + Calendar Reminders toggles
- New API methods: `TodosAPIClient.deleteAccount()`, `TodosAPIClient.disconnectEmail()`

### iOS: Phase 3 — AI Context Awareness

- `AIChatView` suggestions now tab-aware (Home/Tasks/Email/Calendar each show relevant prompts)
- `AppServices.currentTab` tracks active tab, synced by MainTabView
- AI tone preference synced to `AIChatService.toneInstruction` and injected into system prompt

### iOS: Phase 4 — Session Handling

- `TodosAPIClient` now attempts silent refresh on 401 before marking session expired
- `AuthService.isSessionExpired` flag + `attemptSilentRefresh()` method
- Orange "Session expired — Sign in again" banner in MainTabView

### iOS: Phase 5 — Local Notifications

- New `NotificationService.swift` — UNUserNotificationCenter wrapper with TASK_REMINDER category
- Action buttons: Complete (marks task done) and Snooze 1h (reschedules)
- `TaskCaptureService` schedules/cancels notifications on task create/update/complete/delete
- `TodosApp.swift` — AppDelegate adapter for notification action handling

### iOS: Phase 6 — Database Schema Changes

- Added `emailThreadId` and `eventId` columns to task table in `schema.ts`
- Added indexes: `task_email_thread_id_idx`, `task_event_id_idx`
- Updated `TaskRecord.swift` with new optional properties
- Updated tRPC routes (create, update, sync) to accept and persist both fields

### Files Changed

- `PRD.md`, `AGENTS.md`, `CLAUDE.md`, `APPS_ARCHITECTURE.md`
- `apps/ios/Todus/Todus/App/AppServices.swift`
- `apps/ios/Todus/Todus/App/TodosApp.swift`
- `apps/ios/Todus/Todus/Data/Models/TaskRecord.swift`
- `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`
- `apps/ios/Todus/Todus/Features/Calendar/CalendarPermissionView.swift` (new)
- `apps/ios/Todus/Todus/Features/Home/HomeView.swift`
- `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`
- `apps/ios/Todus/Todus/Services/API/TodosAPIClient.swift`
- `apps/ios/Todus/Todus/Services/Auth/AuthService.swift`
- `apps/ios/Todus/Todus/Services/NetworkMonitor.swift` (new, from prior session)
- `apps/ios/Todus/Todus/Services/Notifications/NotificationService.swift` (new)
- `apps/ios/Todus/Todus/Services/Tasks/TaskCaptureService.swift`
- `apps/server/src/db/schema.ts`
- `apps/server/src/trpc/routes/tasks.ts`

---

## [2026-03-27] Review follow-up — OTP fallback, compose draft carry-over, and iOS sync/status fixes

### Fixed

- **OTP fallback is now dev-only**: The server no longer retries all failed OTP sends through `resend.dev`. Fallback is restricted to the owner mailbox in non-production environments so normal users are not routed into an impossible delivery path.
- **CreateSheet email drafts now preserve typed text**: Choosing the Email route from the universal create modal now carries the entered text into `EmailComposeView(body:)` instead of discarding it.
- **Reminders sync direction now affects behavior**: The selected direction now governs both initial bootstrap sync/import and live task mutations, so `From Reminders` no longer pushes app changes back out and `To Reminders` no longer imports reminders into Todus.
- **Calendar connection state now recognizes full access**: Settings correctly treats EventKit `fullAccess` as connected, matching the event creation flow on newer iOS versions.
- **Gmail connect screen now refreshes connection state**: After the Gmail consent flow completes, the email tab re-checks the backend connection and loads threads immediately when access is available.
- **Sensitive auth logs were removed from release paths**: Apple auth response logging and Google callback logging in iOS now avoid writing cookies or callback tokens into device logs.
- **Todus simulator build blockers were resolved**: The Xcode target now includes `NetworkMonitor.swift` and `CalendarPermissionView.swift`, and the tracked `CustomTabBar.swift` has been brought back in sync with the implementation expected by `MainTabView`.

### Files

- `apps/server/src/lib/auth.ts`
- `apps/ios/Todus/Todus/App/AppServices.swift`
- `apps/ios/Todus/Todus/Services/Reminders/RemindersSyncState.swift`
- `apps/ios/Todus/Todus/Services/Tasks/TaskCaptureService.swift`
- `apps/ios/Todus/Todus/Navigation/CreateSheet.swift`
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/Features/Home/HomeView.swift`
- `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailConnectView.swift`
- `apps/ios/Todus/TASK.md`

## [2026-03-27] iOS Create Flow — custom modal overlay + adaptive inputs by type/tab

### Changed

- **`+` action now opens a modal overlay (not system sheet)**: Replaced the old `sheet`-based create UI with an in-app modal overlay that matches the compact floating style.
- **Adaptive create form by selected type**:
  - **Auto**: smart routing (date text -> event, email intent -> email, otherwise task)
  - **Task**: title input + folder selector + due-date picker
  - **Event**: title input + event date/time picker
  - **Email**: title/input mode that opens email compose flow
- **Context-aware defaults by active tab**:
  - **Calendar tab** -> defaults to Event
  - **Tasks tab** -> defaults to Task
  - **Home tab** -> defaults to Auto
  - **Email tab** -> defaults to Email
- **Folder selector default**: Defaults to `Inbox` (no folder) as requested.

### Files

- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/Navigation/CreateSheet.swift`

## [2026-03-27] iOS Tab Screens — unified top header across all tabs

### Changed

- **Shared top header**: Added a reusable `AppTopHeader` for tab root screens with:
  - user avatar on the top-left (profile image or initials fallback),
  - large page title below,
  - dual-action pill on the top-right.
- **Dual actions**: Added two utility actions in the right pill:
  - notifications button (opens iOS notification settings),
  - more/settings button (opens app Settings sheet).
- **Applied on all tab roots**:
  - Home
  - Tasks
  - Inbox
  - Calendar

### Files

- `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift`
- `apps/ios/Todus/Todus/Features/Home/HomeView.swift`
- `apps/ios/Todus/Todus/Features/Tasks/TasksTabView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`

## [2026-03-27] iOS Calendar — create events on tap (no long-press required)

### Fixed

- **Tap-to-create on timeline**: Tapping an empty time slot in the calendar now immediately starts creating a new event.
- **Long-press still supported**: Existing long-press creation behavior remains available.

### Files

- `apps/ios/Todus/Todus/Features/Calendar/CalendarViewController.swift`

## [2026-03-27] iOS Onboarding — visual restyle + real provider logos

### Changed

- **Onboarding visual refresh**: Restyled onboarding layouts to match the app's current spacing, typography, and button rhythm used elsewhere in iOS.
- **Real provider logos**: Replaced generic SF Symbol icons with the same branded provider icons used in Settings:
  - Gmail onboarding now uses `GmailIconView`
  - Reminders onboarding now uses `AppleRemindersIconView`
- **Primary CTA alignment**: Added small provider logos inside the primary connect buttons for stronger visual consistency and recognizability.

### Files

- `apps/ios/Todus/Todus/App/GmailOnboardingView.swift`
- `apps/ios/Todus/Todus/Features/Settings/RemindersSetupView.swift`

## [2026-03-27] iOS Auth, AI Sheet, and Inbox Avatars — autofill + interactive half sheet + robust fallbacks

### Auth

- **Email OTP autofill improvements**: Login email field now uses iOS email autofill hints (`textContentType(.emailAddress)`) and supports submit from keyboard. OTP field keeps native one-time-code autofill and uses a done submit label.

### AI Chat Sheet

- **Half-page AI sheet**: AI chat now opens with a 50% height detent and can expand to full screen.
- **Background remains interactive at half detent**: Enabled background interaction up to the half detent so underlying page context remains visible and scrollable while the AI sheet is half-open.

### Inbox Avatars

- **No more blank avatar slots**: Sender avatar view now always renders initials with a colored circle as a guaranteed base layer.
- **More resilient fallbacks**: Added local domain fallback URL waterfall (`/favicon.ico`, `apple-touch-icon`, DuckDuckGo icon API, Google S2 favicon) when backend avatar resolution is slow/fails.
- **Subdomain and edge-case handling**: Added normalization + root-domain extraction with common multi-part TLD support (`co.uk`, `com.au`, etc.) and `www.` host variants.
- **Cache normalization**: Avatar cache now keys by normalized lowercase email to avoid misses from casing/whitespace differences.

### Files

- `apps/ios/Todus/Todus/Features/Auth/AuthView.swift`
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/Features/Email/SenderAvatarView.swift`

## [2026-03-27] iOS — Custom glass tab bar (two-pill layout)

### Changed

- **Replaced system TabView** with a fully custom tab bar using `safeAreaInset(edge: .bottom)` — eliminates `tabViewBottomAccessory` full-width stretching issues entirely.
- **Two-pill layout**: left pill (4 nav tabs, fills width) + right pill (AI + Create, fixed size). Active tab shows filled icon + subtle blue rounded-rect indicator.
- **Glass material**: iOS 26 uses `.glassEffect(in: Capsule())` (Liquid Glass); iOS 17/18 uses `.ultraThinMaterial` capsule + drop shadow.
- **AI icon**: `lasso.badge.sparkles` with `.symbolRenderingMode(.multicolor)` for colorful rendering.
- **Create button**: "+" inside a small `Color.primary` filled circle (inverts in dark mode).
- **Content inset**: `safeAreaInset` pushes all content up automatically — no manual padding needed per-view.

### Files

- `apps/ios/Todus/Todus/Navigation/CustomTabBar.swift` ← new
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift` — stripped to content+safeAreaInset only

## [2026-03-27] iOS Settings — Native logout confirmation modal

### Changed

- **Logout confirmation**: Added native iOS confirmation dialog before signing out from the Settings account section. Tapping "Log out" now first shows a destructive confirm step with cancel option.

### Files

- `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`

## [2026-03-27] iOS Settings overhaul — Google avatar, functional toggles, sync direction, brand icon fix

### Account Section

- **Google avatar + name**: Account card now shows AsyncImage from Google profile URL, display name, and email. Falls back to letter-initial circle if no image. `fetchUserProfile()` called on auth completion and when settings opens.
- **Logout moved into account card**: Removed standalone logout section; logout button now lives inside the Account section card.
- **Removed "Signed in" badge**: Email address shown below name instead.

### Email Section (functional toggles)

- **Swipe Gestures**: Toggle now bound to `services.swipeGesturesEnabled` (was static).
- **Email Signature**: Toggle bound to `services.signatureEnabled`; inline text field appears when enabled, bound to `services.signatureText`.
- **Thread Grouping**: Toggle bound to `services.threadGroupingEnabled` (was `.constant(true)`).

### Reminders Sync Direction

- **`RemindersSyncDirection` enum** added to `SyncModels.swift`: `.twoWay`, `.toReminders`, `.fromReminders` with titles, subtitles, icons.
- **RemindersSetupView**: Added inline picker for sync direction (shown when sync is enabled).

### Icons on all settings items

- Added `Label(_, systemImage:)` to AI, Preferences, About, Privacy sections.

### Brand Icon Fix

- Added `.aspectRatio(1, contentMode: .fit)` to `GmailIconView`, `AppleCalendarIconView`, `AppleRemindersIconView` to prevent stretching.

### Files

- `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift` — Full rewrite
- `apps/ios/Todus/Todus/Features/Settings/RemindersSetupView.swift` — Sync direction picker
- `apps/ios/Todus/Todus/Domain/SyncModels.swift` — RemindersSyncDirection enum
- `apps/ios/Todus/Todus/DesignSystem/BrandIcons.swift` — 1:1 aspect ratio fix
- `apps/ios/Todus/Todus/Services/Auth/AuthService.swift` — fetchUserProfile on auth completion

## [2026-03-27] iOS Email — Clean minimal redesign, glass buttons, star + mark-unread

### Thread View

- **Header redesign**: Glass icon buttons (34×34) for back, star, mark-as-unread, archive, trash. Subject + sender name shown inline. Star derived from thread labels; toggles optimistically.
- **Mark as unread**: Taps `markAsUnread` + dismisses to inbox so the row shows unread immediately.
- **Cleaner message bubbles**: Sender row is a tap target for collapse; body has an inset section with hairline divider. Softer `rowStroke` border.
- **Header material**: `.ultraThinMaterial` with divider overlay.

### Inbox

- **Row separators**: `listRowSeparator(.visible)` with `AppTheme.divider` tint.
- **Loading indicator**: Inline spinner next to "Inbox" title during refresh.
- **Glass search bar**: `.glassEffect(in:)` on iOS 26; surface card fallback.
- **Unread accent bar**: 3pt vertical bar on left edge instead of floating dot.
- **Settings button**: Now uses `LiquidGlassButtonStyle`.

### Files

- `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailRowView.swift`

## [2026-03-27] iOS Settings — Full overhaul with brand icons, better appearance, more options

### Bug Fix

- **Settings buttons now work**: `hasSeenOnboarding` on `AuthService` changed from a computed UserDefaults property to a stored `@Observable` var. SwiftUI now detects the change and `RootView` correctly switches to `AuthView` when the user logs out or taps "Sign in". Previously, no observable change occurred when `authState` was already `.guest`. (`AuthService.swift`)
- **Cards visible in light mode**: `AppTheme.backgroundBottom/Top` changed from `0.99` to `0.94` in light mode, matching iOS `systemGroupedBackground`. List cells (white) now contrast clearly against the gray background. Dark mode surface raised slightly `0.09 → 0.11` to reduce harsh contrast. (`AppTheme.swift`)

### Feature: Brand Icons

- **`BrandIcons.swift`** (new): `GmailLogo` — pixel-accurate SVG-path recreation using `Canvas` + five filled paths (blue/green/yellow/red/dark-red). `AppleCalendarLogo` — red header + large day number. `AppleRemindersLogo` — three coloured dot rows. All wrapped in `AppIconContainer` with iOS-style rounded-rect background and shadow. (`BrandIcons.swift`)

### Feature: Improved Settings UI

- **Appearance selector**: Replaced `.segmented` picker with three visual preview cards (mini mock-UI swatch + icon + label). Selection shows blue border + checkmark. (`SettingsView.swift`)
- **Account section**: Avatar circle with email initial, green/orange status dot, cleaner layout.
- **Connected Services**: Proper brand icons with connection status. Apple Calendar shows "Connect" button when not authorized.
- **New sections**: Email (thread grouping, unsubscribe, signature, swipe actions), AI Assistant (task read/write toggles), Privacy (app permissions, data sync info).
- **AI model picker**: Developer section `Model` row is now a `Picker` showing all `preferredModels`, directly bound to `aiChatService.selectedModel` via `@Bindable`.
- **Log out button**: Always says "Log out" (was conditionally "Return to Login"). (`SettingsView.swift`)

## [2026-03-27] iOS Thread View — Auto-height body, swipe back, liquid glass, AI summary

### Bug Fix

- **Email body no longer clipped**: Replaced fixed `maxHeight: 600` frame with dynamic WKWebView height measurement (`document.documentElement.scrollHeight` via `evaluateJavaScript`). Two-pass measurement (immediate + 700ms delay) handles late-loading images. Emails now expand to full content height.
- **`markAsRead` reliability**: Replaced `async let _ = markAsRead` with a named `async let` plus explicit `await` so the read request is not dropped (Swift structured-concurrency pitfall, see Swift #62027).
- **WKWebView flicker**: `EmailHTMLView.updateUIView` only calls `loadHTMLString` when raw `html` changes, not when height measurement updates state — avoids redundant reloads per message.

### Feature: Swipe-to-go-back

- **`SwipeBackEnabler`** (new in `AppTheme.swift`): `UIViewControllerRepresentable` that re-enables `interactivePopGestureRecognizer` after `.navigationBarBackButtonHidden(true)`. Applied to `EmailThreadView`.

### Feature: Liquid Glass Reply Button

- **`LiquidGlassButtonStyle`** (new in `AppTheme.swift`): Uses `.glassEffect(in:)` on iOS 26+, falls back to surface+border card on older iOS. Reply bar uses this style.

### Feature: AI Summary Card

- **`AISummaryCard`**: Collapsible summary at the top of the thread. Calls `brain.generateSummary` tRPC endpoint (uses `@cf/facebook/bart-large-cnn` — Cloudflare Workers AI, free tier). Only shown when the brain has vectorized the thread. Styled with a purple accent border matching the web app.

### Refactor

- `MessageBubble` now uses `SenderAvatarView` (size: 32) instead of its own initials/color logic.
- `EmailHTMLView` extracted into `ExpandingEmailHTMLView` wrapper — cleaner height state management.

### Files

- `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift`
- `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift`
- `apps/ios/Todus/Todus/Features/Email/SenderAvatarView.swift` (added `size` param)

## [2026-03-27] iOS Inbox — Real Sender Avatars with Fallback Chain

### Feature

- **`SenderAvatarView`**: New SwiftUI component that resolves real sender avatars via the existing backend `avatar.getByEmail` tRPC endpoint (Google People API → domain favicon → fallbacks → initials).
- **`AvatarCache`**: `@Observable` singleton that deduplicates in-flight requests and caches results for the session. Views re-render automatically when a cache entry arrives.
- **Waterfall fallback**: `AsyncImage` tries URLs in priority order; advances to next on load failure, ending at initials + deterministic color circle if all fail.
- **Subdomain handling**: Handled by the backend — `auth.supabase.com` resolves to the Supabase root-domain logo.

### Files

- `apps/ios/Todus/Todus/Features/Email/SenderAvatarView.swift` (**new** — add to Xcode project)
- `apps/ios/Todus/Todus/Features/Email/EmailRowView.swift` — replaced inline initials avatar with `SenderAvatarView`

## [2026-03-27] iOS Tab Bar — HIG-Compliant Layout, Calendar Fix, Floating Action Pill

### Structural Fix

- **Separated tabs from actions**: Removed `tabViewBottomAccessory` and `safeAreaInset` accessory patterns. Both caused the action buttons to stretch full-width and merge visually with the tab bar, violating Apple HIG (tabs = navigation, actions ≠ tabs).
- **Floating action pill**: AI and Create buttons now live in a compact vertical pill (~44×88pt, glass material) that floats bottom-right above the tab bar — clearly a separate control, not a tab.

### Calendar Clipping Fix

- **Removed double NavigationStack**: `CalendarContainerView` creates its own `UINavigationController` internally. Wrapping it in another `NavigationStack` from `tabContent(for:)` broke safe-area propagation, causing the bottom ~30% of calendar content to be clipped behind the tab bar.

### Tint Color Fix

- **`AppTheme.accentBlue`**: Changed from `Color(red: 0.25, green: 0.48, blue: 1.0)` (purple-shifted) to `Color.blue` (system iOS blue, matches `AppPrimaryButtonStyle`).

### Files Updated

- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift`

## [2026-03-26] UX Fixes — Usability, Touch Support & Discoverability

### Critical Fixes

- **Security settings**: Replaced non-functional 2FA toggle and Delete Account button with clear "Coming soon" state. Prevents users from thinking they've enabled security features that don't exist yet. (`settings/security/page.tsx`)
- **Thread action toolbar touch support**: Action buttons (star, archive, delete) now visible when a thread is selected/focused, not just on hover. Touch devices (tablets, phones) can now access these core actions. Added `@media (pointer: coarse)` CSS rule for broader touch support. (`mail-list.tsx`, `globals.css`)

### High-Impact Improvements

- **CC/BCC toggle visibility**: Replaced invisible plain-text Cc/Bcc buttons with styled toggle buttons that show active state (blue highlight when enabled). Much more discoverable in compose view. (`email-composer.tsx`)
- **Keyboard shortcuts overlay**: New `?` key shortcut opens a grouped, scrollable dialog showing all keyboard shortcuts organized by scope (Navigation, Global, Mail List, Thread, Compose). Replaces the old behavior of navigating away to settings. (`keyboard-shortcuts-dialog.tsx`, `hotkey-provider-wrapper.tsx`)
- **Context-sensitive empty states**: Mail list empty state now shows "No results found" with "clear filters" action when searching, vs. "No emails in this folder yet" when the folder is genuinely empty. (`mail-list.tsx`)

### Medium Fixes

- **iOS swipe-to-go-back**: Restored native swipe-back gesture in `EmailThreadView` by using `.navigationBarBackButtonHidden(true)` instead of `.toolbar(.hidden)`. Custom back button still renders, but iOS swipe gesture now works. (`EmailThreadView.swift`)

### Verified Working (no changes needed)

- **Undo toasts**: Archive/delete already have undo toasts with delayed execution — confirmed working via `createPendingAction` in `use-optimistic-actions.ts`.
- **Connections page**: Legitimate user-facing feature (manage connected email accounts), not debug info.
- **Category selection**: Uses dropdown with checkmarks — clear selected state already present.

## [2026-03-26] iOS Performance — Fix Hangs & UI Freezes

### Computed Property Caching (HIGH impact)

- **CalendarTaskView**: `buckets` computed property now cached in `@State`, recomputed only on `allTasks`/`searchText`/`selectedFolderID` changes instead of every body evaluation.
- **HomeView**: `tasksDueToday` cached in `@State`, recomputed on `allTasks` change.
- **EmailInboxView**: `filteredThreads` cached in `@State`, recomputed on `searchText`/`threads` change.
- **TaskTableView**: `visibleTasks` cached in `@State`, recomputed on `allTasks`/`selectedFolderID` change.
- **BoardView**: `filteredTasks(for:)` (called 4x per render) replaced with pre-grouped `@State` dictionary computed once.

### Startup Parallelization

- **RootView**: Auth upgrade and reminders setup now run concurrently via separate `.task` modifiers instead of sequentially.

### Settings Sheet Binding

- **MainTabView**: Replaced inline `Binding(get:set:)` with proper `@Bindable` pattern for `showsSettings`.

### Email Service Optimization

- **EmailService**: Batched parallel thread fetches into groups of 8 (was 30 simultaneous requests).

### Bug Fixes

- **EmailModels**: Fixed `EmailMessage` and `EmailAttachment` `Codable` → `Decodable` (they're only decoded from API responses, custom `CodingKeys` prevented `Encodable` synthesis).
- **EmailThread**: Added `Equatable` conformance for `.onChange(of:)` support.

## [2026-03-26] UI Polish — Refined Design Tokens, Typography & Visual Consistency

### Design Token Refinements (globals.css)

- **Softened foreground colors**: Light mode foreground moved from near-pure-black `hsl(240 10% 3.9%)` to softer `hsl(240 6% 13%)`. Dark mode foreground eased to `hsl(0 0% 93%)`.
- **Warmed backgrounds**: Light bg shifted to `hsl(0 0% 99%)`, dark bg to `hsl(240 4% 7.5%)`. Static hex colors use slightly warm grays instead of pure blacks.
- **Tightened typography**: Base letter-spacing set to `-0.011em`, headings to `-0.02em`. Body line-height `1.5`, heading line-height `1.2`. Font smoothing enabled globally.
- **Softer borders/rings**: Border and ring values use slightly more neutral hues with lower saturation.

### Component Updates

- **button.tsx**: Text tightened to `13px`, transitions smoothed to `150ms`.
- **card.tsx**: Rounded from `2xl` to `xl`, shadow softened. Card title from `2xl` to `lg`. Padding tightened from `p-6` to `p-5`.
- **input.tsx**: Height from `h-10` to `h-9`, rounded from `xl` to `lg`, text `13px`.
- **settings-card.tsx**: Removed hardcoded `panelLight/panelDark` for `transparent`. Tighter spacing.

### Sidebar Refinements

- **Removed purple upgrade button** (`#8B5CF6` → `mainBlue`). Tighter spacing and smaller text.
- **Compose button**: Uses `mainBlue` token. Smoother transition.
- **Sidebar padding**: Reduced from `px-4` to `px-3` for tighter layout.
- **Nav section titles**: Changed from `13px` to `11px uppercase tracking-wide` for clear visual hierarchy.
- **Hover states**: Replaced hardcoded `bg-subtleWhite`/`dark:bg-[#202020]` with `bg-accent` token.

### Navigation & User Area

- **Replaced 20+ hardcoded hex colors** (`dark:bg-[#131313]`, `dark:bg-[#141414]`, `text-black dark:text-white`, etc.) with semantic tokens (`bg-popover`, `bg-card`, `text-foreground`, `bg-background`).
- **Tighter user info section**: Reduced spacing between name, email, and verification badge.

### Login Page

- **Tighter layout**: Narrowed max-width to `340px`, reduced padding and heading sizes.
- **Typography**: Headings from `2xl` to `xl`, links from `text-xs` to `11px`.
- **Showcase panel**: Rounded from `2.5rem` to `2xl`, softened border/shadow.

### Mail List (thread items)

- **Hover**: Replaced `bg-offsetLight`/`dark:bg-primary/5` with `bg-accent/60` + `transition-colors`.
- **Action bar**: Tightened from `rounded-xl p-1 gap-1` to `rounded-lg p-0.5 gap-0.5` with softer shadow.
- **Unread dot**: Smaller (`1.5` from `2`), uses `mainBlue` token.
- **Date text**: Reduced to `11px`.
- **Content preview**: Tighter margins, `12px` text.
- **Removed all hardcoded tooltip backgrounds** (`bg-white dark:bg-[#1A1A1A]`).

### Thread Display

- **Container**: Replaced `bg-panelLight dark:bg-panelDark` with `bg-card`.
- **All action buttons**: Replaced `bg-white dark:bg-[#313131]`/`hover:bg-gray-100 dark:hover:bg-[#404040]` with `bg-card hover:bg-accent`.
- **Reply button**: Cleaner token-based styling.
- **Empty state**: Tighter text sizes, token-based colors.

### Settings Layout

- **Replaced all hardcoded border/bg colors** with `border-border/60` and `bg-card`.
- **Slightly tighter padding** and reduced shadow.

### iOS Refinements

- **AppTheme.swift**: Slightly adjusted dark mode background from `0.04` to `0.05` white, surface values nudged 1% lighter. Border opacities reduced for subtlety. Shadow reduced from `0.08` to `0.06`.
- **EmailInboxView**: Inbox header font `28→24` with tighter tracking. Search bar corners `16→12`, thinner border.
- **EmailThreadView**: Subject font `17→16` with tracking. Reply bar height `44→42`, corners `14→12`.

### Files Updated

- `apps/mail/app/globals.css`
- `apps/mail/components/ui/button.tsx`
- `apps/mail/components/ui/card.tsx`
- `apps/mail/components/ui/input.tsx`
- `apps/mail/components/ui/app-sidebar.tsx`
- `apps/mail/components/ui/nav-main.tsx`
- `apps/mail/components/ui/nav-user.tsx`
- `apps/mail/components/ui/settings-content.tsx`
- `apps/mail/components/settings/settings-card.tsx`
- `apps/mail/components/mail/mail-list.tsx`
- `apps/mail/components/mail/thread-display.tsx`
- `apps/mail/components/mail/mail.tsx`
- `apps/mail/app/(auth)/todus/login/page.tsx`
- `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift`

## [2026-03-26] iOS — Replace Custom Tab Bar with System Liquid Glass TabView

### Changed

- **MainTabView**: Replaced the hand-made HStack tab bar with iOS 26's system `TabView` using the new `Tab("Title", systemImage:, value:)` API. The system now renders the Liquid Glass floating bar automatically.
- **Tab selection persistence**: Switched from `@State` to `@SceneStorage("selectedTab")` so the last-used tab is restored across scene sessions.
- **Minimize on scroll**: Added `.tabBarMinimizeBehavior(.onScrollDown)` so the bar shrinks to a pill when scrolling content.
- **Bottom accessory**: Moved the "+" create and AI sparkles buttons into `.tabViewBottomAccessory` — they now float correctly above the glass bar.
- **Accent colors**: Added `AppTheme.accentBlue` (rgb 0.25/0.48/1.0) and `AppTheme.mutedGray` to the design system. Active tab uses accent blue via `.tint()`.
- **AppTab.title**: Added a `title` computed property for human-readable tab labels.
- **Removed padding hacks**: Removed 60–90pt bottom padding workarounds in TasksTabView, EmailInboxView, and EmailThreadView that compensated for the old custom bar.

### Files Updated

- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/Navigation/AppTab.swift`
- `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift`
- `apps/ios/Todus/Todus/Features/Tasks/TasksTabView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift`

## [2026-03-26] Deploy Command Parsing Clarification (Docs)

### Fixed

- **Deploy Usage**: Clarified that inline `# ...` text after `pnpm run` commands may be forwarded as real CLI args to Wrangler (triggering `Unknown arguments`), and showed the correct deploy commands (`pnpm run deploy:backend` / `pnpm run deploy:frontend`). (docs/terminal-commands.md)
- **Env Selection**: Updated deployment docs to run Wrangler via `pnpm --filter=... exec wrangler` and explicitly pass `-e staging` / `-e production` (avoids relying on pnpm script argument passthrough and fixes “wrangler: command not found”). (docs/terminal-commands.md)

## [2026-03-11] Sender Avatar Resolution Upgrade

### Changed

- **Sender Avatars**: Replaced the previous inbox sender-avatar fallback chain of `BIMI -> external image API -> initials` with a server-backed resolver that now prefers `Google People contact photos -> BIMI -> sender domain favicon`.
- **Cross-Platform Consistency**: Updated both the web mail client and the native iOS inbox/thread sender avatars to use the same server response and favicon fallback list.

### Notes

- **Google Reconnect Requirement**: Existing Google connections may need to reconnect before contact-photo lookups work, because the new resolver requires Google Contacts read scopes in addition to the existing Gmail scopes.

## [2026-03-08] AI Chat Billing Gate UX Fix

### Fixed

- **AI Chat Placeholder**: Restored visible placeholder text in the web AI chat composer by adding explicit Tiptap placeholder rendering styles.
- **Billing Gate Submit Guard**: Prevented `Enter` from submitting AI chat requests when `chat-messages` billing is disabled, so free/blocked states now open the pricing dialog instead of throwing a generic `useChat` error.

## [2026-03-08] Composer AI GPT-5 Compatibility

### Fixed

- **Email Composer AI**: Updated the server-side composer and subject-generation OpenAI calls to use GPT-5-compatible completion token options, fixing 500 errors when generating subjects or drafting content from the email composer.

## [2026-03-05] Login Refinement & Email Connection Guard

### Added

- **Connection Guard**: Implemented `ConnectionWrapper` for the web app, forcing users with 0 email connections (e.g., Apple Sign-in or Email/Password) to link a provider before accessing the mail UI.
- **Backend Graceful Failure**: Updated `activeConnectionProcedure` to throw `NOT_FOUND` instead of signing the user out when no connection exists.

### Fixed

- **Login Screen (iOS)**:
  - **Apple Auth Cancellation**: Gracefully handle `ERR_REQUEST_CANCELED` and similar codes to prevent error popups when users cancel authentication.
  - **Isolated Loading States**: Split Google and Apple loading states so activity spinners only show on the pressed button.
  - **Button Spacing**: Reduced gap between Google and Apple buttons to exactly 16px (1rem).
  - **Logo Balance**: Resized the top-left logo from 32px to 24px for a more balanced aesthetic with the "Todus" wordmark.

## [2026-03-02] Login UI & Logo Visibility

### Fixed

- Fixed logo visibility on iOS login screen by implementing adaptive `tintColor` (black for light mode, white for dark mode).
- Removed native iOS navigation header from login screen to match web app aesthetic.

### Changed

- Updated iOS login screen to better align with web app layout and typography.

## [2026-03-01] App Consolidation + Archive Cleanup

### Changed

- Consolidated active app surface to:
  - `apps/ios` (only active iPhone native app)
  - `apps/macos` (only active desktop webview wrapper)
- Archived duplicate/legacy app implementations to `apps/archived/*`:
  - `apps/native` -> `apps/archived/native`
  - `apps/webview-swift` -> `apps/archived/webview-swift`
  - `apps/apple` -> `apps/archived/apple`
- Removed `native:*` scripts from root `package.json` to prevent accidental double-build paths.

### Updated

- Updated app structure and scripts documentation to reflect the canonical targets.
- Renamed remaining archived native Xcode display/product naming from `Zero*` to `Todus` (display/product/module identifiers in archived native projects).

## [2026-03-01] EAS Build Configuration

### Added

- **EAS Project ID**: Added `extra.eas.projectId` to `apps/ios/app.config.ts` for EAS builds
- **App Version Source**: Set `cli.appVersionSource` to `"local"` in `apps/ios/eas.json` to use app.config.ts version

### Files Modified

- `apps/ios/app.config.ts` - Added EAS project ID (10b2cbe2-6786-4328-a831-ba6ccbca1e89)
- `apps/ios/eas.json` - Added appVersionSource configuration

## [2026-03-01] App Structure Reorganization

### Changed

- **apps/apple → apps/webview-swift**: Moved SwiftUI WebView wrapper to clearly indicate it's a legacy wrapper, not the primary native app (`apps/apple/` → `apps/webview-swift/`).
- **apps/native deprecation**: Marked `apps/native` as deprecated in favor of `apps/ios` which is more complete and TestFlight-ready. Added `DEPRECATED.md` to guide developers to the correct app.

### Added

- **APPS_STRUCTURE.md**: Comprehensive documentation of all apps in the monorepo with status, purpose, and recommended usage.
- **APPS_NATIVE_MIGRATION.md**: Migration plan for deprecating `apps/native` in favor of `apps/ios`.
- **SCRIPTS_GUIDE.md**: Quick reference guide for all package.json scripts with explanations and recommended workflows.

### Architecture Decision

**Primary Apps Going Forward**:

- **Web**: `apps/mail` (Next.js)
- **iOS**: `apps/ios` (Expo React Native) - TestFlight ready
- **macOS**: `apps/macos` (Electron wrapper)
- **Backend**: `apps/server` (Cloudflare Worker)

**Deprecated/Legacy**:

- `apps/native` - Less complete than apps/ios, only kept for potential macOS React Native development
- `apps/webview-swift` - Simple WebView wrapper, not a true native app

## [2026-03-08] Local Mail Auto-Sync Fallback

### Fixed

- **Local Inbox Freshness**: Added a local-only auto-sync fallback that periodically triggers the existing `mail.forceSync` path and refreshes the inbox data, so new emails appear during local development without relying on Gmail push webhooks.
- **Production Safety**: Kept this behavior gated to Vite dev sessions pointed at a localhost backend, leaving staging and production mail sync behavior unchanged.

## [2026-03-08] Local tRPC Rate Limit Fallback

### Fixed

- **Local Settings/Labels 500s**: Resolved `settings.get` and `labels.list` failing with `Invalid token` when the local Redis/Upstash token is expired or mismatched.
- **tRPC Redis Resilience**: Updated `apps/server/src/trpc/trpc.ts` so rate-limited procedures keep working in `local` and `development` when Redis is unavailable, while still enforcing rate limits normally when Redis is healthy.

## [2026-03-01] Login Page Styling

### Changed

- **Auth Layout**: Redesigned the `login` and `signup` pages to a 2-column layout. The left column now hosts the authentication form with a top-left logo placement, while the right column displays a beautifully padded, high-radius hero image (`email-preview.png`) (`apps/mail/app/(auth)/todus/login/page.tsx`, `apps/mail/app/(auth)/todus/signup/page.tsx`).
- **Typography & Details**: Adjusted typography to match requests—"Your AI agent for emails" is now at parity with header size but muted, and sub-text changed to "Sign up for free with your email".

## [2026-03-01] Google OAuth 500 Fix & Redis Robustness

### Fixed

- **OAuth Callback**: Resolved a 500 Internal Server Error during Google OAuth login caused by an invalid `REDIS_TOKEN`.
- **Redis Resilience**: Implemented a `try/catch` fallback mechanism in `apps/server/src/lib/auth.ts` to gracefully switch to PostgreSQL session storage if Redis connection fails (e.g., due to expired/invalid tokens).
- **Cleanup**: Removed temporary debug instrumentation from `main.ts`.
- **Onboarding Assets**: Fixed broken image/animation links in the onboarding modal by switching from non-resolving `assets.todus.app` to local `/public/onboarding` assets.

## [2026-02-27] Frontend Stability & Environment Config Fixes

### Fixed

- **App Crashes**: Resolved `TypeError: Cannot read properties of undefined (reading 'id')` by adding protective optional chaining for `session?.user?.id` inside various frontend hooks and components.
- **Environment Variables**: Fixed `VITE_PUBLIC_BACKEND_URL` resolving to `undefined` on Cloudflare Pages (which broke Sentry and Autumn API calls) by refactoring `vite.config.ts` to properly inject explicit `process.env` definitions via `loadEnv`.
- **API Auth Errors**: Fixed `401 Unauthorized` errors on `/api/autumn/customers` cross-origin calls by passing `includeCredentials={true}` to `AutumnProvider` to ensure session cookies are sent to the backend.

## [2026-02-27] tRPC Errors & UI Polishing

### Fixed

- **tRPC API**: Resolved 500 Internal Server Error in `brain.generateSummary` caused by missing Vectorize indexes (`VECTOR_GET_ERROR`) by implementing a try-catch fallback.
- **UI Warnings**: Fixed `react-resizable-panels` console warnings by strictly defining `id` and `order` properties for all `ResizablePanel` components, and restoring missing `<ResizableHandle />` elements.

## [2026-02-27] Todus Branding & SEO Finalization

### Fixed

- **Rebranding Errors**: Fixed TypeScript lint errors resulting from incomplete rename operations in `auth.ts`, `email-sequences.tsx`, and `sanitize-tip-tap-html.ts`.

### Changed

- **Global Branding**: Renamed "Zero" to "Todus" across configuration, internationalization files (\*.json), static pages, and the footer.
- **Brand Assets**: Updated logo asset URLs, onboarding vide links, and the GitHub repository link to point to Todus domains.
- **Code Settings**: Refactored the signature field from `zeroSignature` to `todusSignature` on both the frontend and the database schema.
- **SEO Elements**: Updated title tags, meta descriptions, and application headers to index correctly for "Todus".

## [2026-02-27] Login UI Polishing & Web Alignment

### Added

- **Colored Google Logo**: Added `GoogleColored` (iOS) and `GoogleColor` (Web) SVG components for better brand recognition.
- **Brand Identity**: Integrated `brand-logo.png` into both iOS and Web login screens.

### Changed

- **UI Copy**: Standardized welcome messaging to "Welcome to Todus" and "Your AI agent for emails".
- **Styling**: Implemented pill-shaped (fully rounded) buttons and inputs for a more modern and premium aesthetic.
- **Theme Support**: Verified full light/dark mode support for the iOS login screen.
- **Compatibility**: Switched iOS from `expo-image` to standard `react-native` `Image` to resolve native module resolution issues.

## [2026-02-25] iOS App: WebView → Native React Native (Expo Router)

### Added

- **Full native iOS app** replacing the Cloudflare WebView wrapper with real React Native screens
- **Expo Router** file-based navigation with Gmail-style drawer, stack, and modal patterns
- **Auth**: OAuth login via Google/Microsoft with bearer token stored in iOS Keychain (expo-secure-store)
- **Mail List**: Thread list per folder (Inbox, Sent, Draft, Starred, Snoozed, Archive, Spam, Trash) via TRPC
- **Thread Detail**: Full message rendering with HTML WebView, archive/delete/spam/star actions
- **Compose**: Email composer with reply/forward mode, To/Cc/Subject/Body fields
- **Search**: Debounced search modal with live thread results
- **Settings**: Hub with General, Appearance (theme toggle), Connections, and Labels screens
- **Drawer Sidebar**: Folder navigation + logout with session clearing
- **Offline caching**: AsyncStorage-backed React Query persistence

### Architecture

- `apps/ios/app/` — Expo Router file-based routes (auth, mail, settings, compose, search)
- `apps/ios/src/` — Providers (TRPC, React Query, Jotai), features (mail, auth, compose), shared (theme, state, storage)
- Ported ~80% of code from `apps/native/` (React Navigation) and adapted for Expo Router
- TypeScript strict mode with zero app-level type errors

### Files Created (~40 new files)

- Config: `babel.config.js`, `metro.config.js`, updated `package.json`, `app.config.ts`, `tsconfig.json`
- Shared: `env.ts`, `secure-storage.ts`, `session.ts`, `ThemeContext.tsx`, `icons.tsx`
- Providers: `AppProviders.tsx`, `QueryTrpcProvider.tsx`, `SessionBootstrap.tsx`
- Auth: `native-auth.ts`, `login.tsx`, `web-auth.tsx`
- Mail: `[folder].tsx`, `thread/[threadId].tsx`, `ThreadListItem.tsx`, `MessageCard.tsx`, `MailSidebar.tsx`
- Compose: `compose.tsx`
- Search: `search.tsx`
- Settings: `_layout.tsx`, `index.tsx`, `general.tsx`, `appearance.tsx`, `connections.tsx`, `labels.tsx`

---

## [2026-02-21] iOS/Mac Wrapper and Todus Branding Updates

### Added

- Added `/docs/terminal-commands.md` with end-to-end startup/build/deploy commands
- Added `/docs/share-asap.md` with fastest distribution path for friends (web + TestFlight)

### Changed

- iOS wrapper now keeps HTTP/HTTPS navigation in-app and starts at `/mail/inbox`
- iOS wrapper now uses safe area/inset behavior to reduce clipped content at top/bottom
- Added env-driven app name support:
  - `VITE_PUBLIC_APP_NAME` (web branding)
  - `EXPO_PUBLIC_APP_NAME` (iOS/macOS wrapper title/loading text)
- Updated visible branding on login/onboarding/navigation/footer/manifest from Zero to Todus in key user-facing surfaces

### Notes

- OAuth browser handoff can still happen depending on Google provider behavior; this is not Supabase-specific in this stack

## [2026-02-08] Local Development Complete ✅

### Milestone

- Successfully logged in via Google OAuth
- Viewing and reading emails works
- Ready to deploy to production

---

## [2026-02-08] Initial Local Development Setup

### Added

- Cloned Mail-Zero repository from `staging` branch
- Set up local Docker Postgres, Redis (Valkey), and Upstash Proxy containers
- Configured `.env` and `.dev.vars` with development credentials
- Initialized database schema via `pnpm db:push`

### Fixed

- **Docker**: Changed Valkey image tag from `8.0` to `latest` (fix for image not found)
- **Twilio**: Made Twilio service optional for local development (returns mock when `TWILIO_PHONE_NUMBER` is missing)

### Environment Files Updated

- `/apps/server/.dev.vars` - Synced with root `.env` credentials
- `docker-compose.db.yaml` - Fixed Valkey image tag

### Notes

- Twilio phone number is NOT required for local development (SMS 2FA is mocked)
- Resend API key is NOT required for local development (email sending is mocked)
- Redis uses `upstash-local-token` which matches the Docker proxy setup

[2026-02-21] [Feature] Integrated real TRPC data for the native Thread list (N3-05) via useQuery hook on MailFolderScreen and ThreadListItem (apps/native/src/features/mail/\*).

[2026-03-01] [Fix] Fixed chat modal opacity overlay, restricted pricing dialog trigger area to primary CTA button, and resolved chat connection Error code 400 by adjusting unsupported gpt-5 model name configuration to gpt-4o. (apps/mail/components/ui/ai-sidebar.tsx, apps/mail/components/create/ai-chat.tsx, apps/server/.dev.vars).

[2026-03-09] [Fix] Added native sender avatars for the iOS mail experience by mirroring the web app's BIMI and domain-logo fallbacks, then tightened inbox row spacing and unread metadata so the mobile inbox reads closer to the web list. User-facing change. (apps/ios/src/features/mail/SenderAvatar.tsx, apps/ios/src/features/mail/ThreadListItem.tsx, apps/ios/src/features/mail/MessageCard.tsx, apps/ios/src/shared/config/env.ts, apps/ios/app/(app)/(mail)/[folder].tsx).

[2026-03-09] [Fix] Restored native thread body rendering by reading `decodedBody` in the message detail card when the server payload does not populate `processedHtml` or `body`. User-facing change. (apps/ios/src/features/mail/MessageCard.tsx).

[2026-03-10] [Fix] Resolved mobile Thread View UI issues including dark mode text, email clipping, large floating actions, and missing sender avatars (apps/ios/src/features/mail/MessageCard.tsx, apps/ios/src/features/mail/ThreadDetailPane.tsx, apps/ios/.env).

[2026-03-10] [Refactor] Flattened Thread View by removing nested cards and backgrounds around emails and notes in iOS app (apps/ios/src/features/mail/MessageCard.tsx, apps/ios/src/features/mail/ThreadDetailPane.tsx).

[2026-03-10] [UI Fix] Replicating web app Thread Layout in iOS. Added missing Reply All icon, matching exact header actions. Shifted floating action pills downwards. Fixed WebView horizontal overflow.

[2026-03-10] [UX Fix] Improved the native iOS inbox flow by replacing the placeholder ellipsis alert with real thread actions, moving notes below message content, hiding raw system labels behind friendlier names, adding inbox gesture discovery guidance, improving empty-state copy, and adding clearer search filter state with reset affordances. User-facing change. (apps/ios/src/features/mail/ThreadDetailPane.tsx, apps/ios/src/features/mail/ThreadListItem.tsx, apps/ios/app/(app)/(mail)/[folder].tsx, apps/ios/app/search.tsx).

[2026-03-10] [Fix] Normalized low-contrast message HTML in the native iOS thread view so dark mode no longer forces white text onto pale email backgrounds. The WebView now removes only broken light backgrounds or low-contrast text combinations instead of applying a blanket dark-mode text override. User-facing change. (apps/ios/src/features/mail/MessageCard.tsx).

[2026-03-10] [UX Fix] Added direct read-state controls to the native iOS mail triage flow: the inbox swipe menu now includes a read/unread action, and the thread header now exposes a dedicated mark read/unread button with optimistic state updates. User-facing change. (apps/ios/src/features/mail/SwipeableThreadRow.tsx, apps/ios/src/features/mail/ThreadDetailPane.tsx, apps/ios/app/(app)/(mail)/[folder].tsx).

[2026-03-10] [UI Polish] Refined the native iOS mail surfaces with a softer monochrome palette, denser typography, cleaner grouping, subtler accent usage, and more card-like hierarchy across inbox, search, and thread detail. User-facing change. (apps/ios/src/shared/theme/ThemeContext.tsx, apps/ios/src/features/mail/ThreadListItem.tsx, apps/ios/src/features/mail/MessageCard.tsx, apps/ios/src/features/mail/ThreadDetailPane.tsx, apps/ios/src/features/mail/SwipeableThreadRow.tsx, apps/ios/src/features/mail/SenderAvatar.tsx, apps/ios/app/(app)/(mail)/[folder].tsx, apps/ios/app/search.tsx).

[2026-03-11] [Fix] Corrected the optimistic read/unread rollback wiring in the native iOS swipe and thread-detail mutations so the new triage controls compile cleanly without changing their behavior. Architectural safety fix. (apps/ios/src/features/mail/SwipeableThreadRow.tsx, apps/ios/src/features/mail/ThreadDetailPane.tsx).

[2026-03-11] [UX Fix] Removed the inbox gesture tip banner, changed the mail compose header button from `+` to a pencil, shifted the remaining native mail palette away from blue/slate tints toward warmer neutrals, and updated sender-avatar fallbacks to request domain logos without generic placeholder fallbacks so missing logos render initials instead of the broken-person icon. User-facing change. (apps/ios/app/(app)/(mail)/[folder].tsx, apps/ios/src/shared/theme/ThemeContext.tsx, apps/ios/src/features/mail/SenderAvatar.tsx).

[2026-03-11] [UI Polish] Reworked the native iOS inbox into a cleaner divided list instead of stacked cards and redesigned the inbox header to foreground account identity with the signed-in avatar plus unread-count status, while preserving search and compose in a secondary action strip. User-facing change. (apps/ios/src/features/mail/ThreadListItem.tsx, apps/ios/app/(app)/(mail)/[folder].tsx).

[2026-03-31] [Feature] Expanded the active web app mail shell toward native parity by adding first-class `/mail/home`, `/mail/tasks`, `/mail/calendar`, `/mail/search`, and `/mail/chat` routes in `apps/mail`, switching `/mail` to land on Home, and upgrading the sidebar navigation to expose the same primary surfaces with expandable Email children. User-facing change. (apps/mail/app/routes.ts, apps/mail/app/(routes)/mail/page.tsx, apps/mail/app/(routes)/mail/home/page.tsx, apps/mail/app/(routes)/mail/tasks/page.tsx, apps/mail/app/(routes)/mail/calendar/page.tsx, apps/mail/app/(routes)/mail/search/page.tsx, apps/mail/app/(routes)/mail/chat/page.tsx, apps/mail/components/ui/nav-main.tsx, apps/mail/components/ui/app-sidebar.tsx, apps/mail/config/navigation.ts).

[2026-04-03] [Fix] Tightened meeting handling by keeping the notes delete confirmation on a real Paraglide key, auto-scheduling future meetings that already exist in sync results, and pruning expired recording media based on the new retention setting. User-facing and architectural change. (apps/mail/components/mail/note-panel.tsx, apps/server/src/trpc/routes/meet.ts, apps/server/src/routes/recall-webhook.ts, apps/server/src/lib/meeting-retention.ts).

[2026-04-03] [UX Fix] Tightened the native iOS Tasks surface by slimming the search/sort controls, reducing task-row padding, and redesigning Calendar mode into a due-date timeline with bucketed cards so it reads differently from List. User-facing change. (apps/ios/Todus/Todus/Features/Tasks/TasksTabView.swift, apps/ios/Todus/Todus/Features/Tasks/TaskRowView.swift, apps/ios/Todus/Todus/Features/Tasks/CalendarTaskView.swift).

[2026-04-03] [UI Polish] Refined the native iOS Tasks board into a more product-like kanban surface with quieter monochrome columns, tighter card typography, clearer empty/add states, a stronger board header treatment, and a more explicit board-mode icon. User-facing change. (apps/ios/Todus/Todus/Features/Tasks/BoardView.swift, apps/ios/Todus/Todus/Features/Tasks/BoardColumnView.swift, apps/ios/Todus/Todus/Features/Tasks/BoardTaskCard.swift, apps/ios/Todus/Todus/Domain/TaskViewMode.swift).

[2026-04-04] [UX Fix] Corrected the cached-refresh loading-state work to target the real web app in `apps/web`, added subtle background update badges across inbox, home, tasks, and calendar, stopped invalidating restored inbox cache on startup, and switched the web home recent-mail panel to render from thread summaries instead of per-row thread fetches. User-facing and architectural change. (apps/web/components/ui/background-refresh-indicator.tsx, apps/web/components/mail/mail-list.tsx, apps/web/app/(routes)/mail/home/page.tsx, apps/web/app/(routes)/mail/tasks/page.tsx, apps/web/app/(routes)/mail/calendar/page.tsx, apps/web/providers/query-provider.tsx).

[2026-04-24] [Tooling Fix] Repointed the root `pnpm ios*` scripts to the active native SwiftUI app in `apps/ios/Todus` so they no longer invoke the archived Expo app and fail with missing Expo module maps. Architectural tooling change. (`package.json`, `scripts/ios/open-native-project.sh`, `scripts/ios/build-native-simulator.sh`, `scripts/ios/build-native-device.sh`, `docs/development/SCRIPTS_GUIDE.md`).

[2026-04-25] [Fix] Closed review-found regressions in AI billing and legacy schema compatibility by hydrating legacy billing state on AI access, billing chat/search usage against the concrete resolved model, and restoring legacy `mail0_connection` fallback reads inside the Zero chat agent. Architectural safety fix. (`apps/server/src/lib/ai-model-resolver.ts`, `apps/server/src/lib/billing.ts`, `apps/server/src/routes/chat.ts`).

[2026-04-26] [Fix] Hardened legacy mail connection fallback detection so wrapped shard/bootstrap errors that still originate from a missing `mail0_connection.color` column no longer bypass the degraded-schema path during startup mail loads and assistant briefing fetches. Architectural safety fix. Manual follow-up: apply the existing backend migration `0047_connection_color.sql` in the environment serving `api.todus.app` to remove the fallback path entirely. (`apps/server/src/lib/server-utils.ts`).

# 2026-04-04

## Fixed

- Prevented duplicate onboarding and marketing emails by adding a database-backed marketing delivery ledger and per-day recipient guardrails in the server auth flow.
- Added a uniqueness constraint and migration-time dedupe for auth accounts so the same provider account cannot create multiple `mail0_account` rows and retrigger onboarding.
- Added a duplicate-audit script for normalized users, auth accounts, and connections to support database cleanup on a live environment.
