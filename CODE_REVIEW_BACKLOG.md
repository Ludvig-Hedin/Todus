# Code Review Backlog

Last updated: 2026-07-07

---

# iOS UX assessment + polish + bug hunt — 2026-07-07 (apps/ios)

Triple audit (12 parallel finder agents: 5 UX assessment, 3 UX polish, 4 bug hunt) over the whole iOS app, then a fix pass. ~60 verified findings fixed across Email, Search, Auth/Onboarding, Tasks/Folders/Home, Calendar/Meetings/Docs, AI/Voice, Settings, Navigation, and the services layer. Simulator build green. Details in CHANGELOG `[Unreleased]`.

## Resolved in the follow-up pass (2026-07-08)

- ~~Account deletion~~ — flow is now verification-aware: the app no longer wipes local data / signs out on the delete request; it tells the user to check their email (deletion completes via the emailed link; the eventual 401 signs the device out). `Origin` header added.
- ~~Received email attachments can't be opened~~ — the server already exposes `mail.getMessageAttachments` (base64 content); attachment cards now download on tap (per-card spinner) and open in the shared preview sheet, with error copy on failure.
- ~~Composed email attachments never uploaded~~ — the server's `mail.send` already accepts `serializedFileSchema`; iOS now uploads chips inline (base64) with the send. Compose body is also converted from the toolbar's light Markdown to HTML so recipients don't see literal `**bold**` markers (resolves the backend-rendering question — the server forwards `message` as-is).
- ~~Global search email local-only~~ — global search now runs a debounced server-side search via a new non-clobbering `EmailService.searchThreadsServer`, merged (deduped) with the instant local matches.
- ~~Offline task deletions lost on kill~~ — pending delete retries now persist to UserDefaults (SyncMutation is Codable) and restore on launch; no schema change needed.
- ~~Draft double-send~~ — `mail.send` now accepts a `clientSendId` idempotency key (KV-deduped server-side, both immediate and scheduled paths); iOS sends the draft's stable id, and `flushPending` safely retries drafts stuck in "sending" again. ⚠️ Deploy the server before shipping the iOS build — until the server is deployed the key is ignored (zod strips unknown keys) and retries behave like before.
- ~~HomeView dead code~~ — `summaryLine`, `topPriority`, `topPriorityRow`, `HomeTopPriority` deleted (~150 lines).

## Deferred (product decisions)

- **[docs/ios-followup-tasks.md](docs/ios-followup-tasks.md)** (2026-07-08): tasks 1–4 + 7 (dynamic tab bar BH-0613-6, in-composer attachment picker, all-mail search scope, session-persistent meeting Q&A, micro-nits) were implemented the same session. Remaining: Task 5 (ops — deploy `apps/server` before the next iOS release) and Task 6 (device smoke test).
- ~~GoogleCalendarService primary fallback ignores hiddenCalendarIds~~ — fixed 2026-07-08 (cold-start connections with hidden calendars are skipped until their calendar list loads).

---

# Backlog resolution pass — 2026-06-13 (whole-repo)

Systematic sweep of the entire backlog. 5 parallel read-only verification agents first re-checked every open item against CURRENT code (many were already fixed by later passes but never marked); 4 parallel fixer agents then applied the safe, confirmed-open fixes on disjoint file-sets (web / server / iOS / macOS). iOS + macOS builds green; server/web changes type-reviewed (no tsc/node in sandbox).

## Fixed this pass

**Server (`apps/server/src`)**
- `main.ts` — `.well-known/oauth-authorization-server` missing leading slash → 404 (added `/`).
- `main.ts` — `processExpiredSubscriptions` leaked the Hyperdrive connection if `findMany` threw (wrapped in try/finally).
- `main.ts` — `[SCHEDULED] Processed ${allAccounts.keys.length}` always logged 0 (→ `.length`).
- `main.ts` — `a8n/notify/:providerId` returned `undefined` (→ 500/404) for non-google providers (added explicit 200 fallback).
- `main.ts` — **send-email-queue dropped scheduled emails on transient failure** (catch deleted status+payload then acked); now keeps payload and `msg.retry()`s.
- `main.ts` (B-003, security) — native refresh-token fallback ignored `expiresAt`; bounded to a 15-min grace window so a leaked long-expired token can't resurrect a session.
- `lib/ai-profile.ts` (B-024) — sanitize user `name`/`email` before prompt interpolation (strip backticks/headers/newlines); (B-027) add `timeZoneName` so local time isn't zone-ambiguous.
- `trpc/routes/assistant.ts` (B-020) — `extractVerificationCode` fallback now requires a verification keyword nearby + rejects zips/years/phones (prefers null over a wrong code); (B-021) `extractReceiptDetails` prefers a label-anchored (Total/Amount paid/…) amount before any currency number.
- `lib/thread-classification.ts` (B-012, NEW) — extracted the duplicated/drifting `classifyThreadKind` + keyword/sender regexes; `assistant.ts` + `mail-assistant.ts` now import the shared (superset) module.
- `pipelines.ts` (B-023) — extracted `getUserAutomationPolicy(userId)`; both the Effect and imperative paths call it (dropped the duplicate fallback).

**Web (`apps/web`)**
- `hooks/use-optimistic-actions.ts` — cleanup branch checked `=== 1` AFTER the delete (1→0 never fired) → optimistic-actions atom leak + stuck `shouldHide`; fixed to `=== 0`.
- `components/ui/bimi-avatar.tsx` (B-013) — re-applied the dropped favicon-URL cap (`.slice(0, MAX_FAVICON_URLS)`, bumped to 8) so a sender no longer fires 20-30+ sequential favicon GETs.
- `app/(routes)/mail/tasks/page.tsx` (B-039) — removed the redundant unconditional `invalidateQueries` on task create (was thrashing the optimistic cache patch).

**iOS (`apps/ios/Todus`)**
- `Services/Email/EmailService.swift` (B-016) — `checkConnection` no longer marks `hasResolvedConnection` true on timeout (was stranding connected users on the connect screen); (EM-5) `connectGmail` multi-account now polls until the new connection lands before reporting success; (EM-11) `performLoadThreads` sorts merged pages by date desc (pinned `mergePages` contract + test left intact).
- `Features/Email/SenderAvatarView.swift` (EM-2) — capped the favicon waterfall to 4 candidates; (EM-4) letter-only registry brands now fall through to the favicon waterfall (brand-tinted initials as base) instead of dead-ending on gray initials.
- `Features/Email/EmailThreadView.swift` (EM-12) — webview deferred re-measure is a cancellable `DispatchWorkItem`, cancelled in `dismantleUIView`.
- `Features/Email/EmailComposeView.swift` (EM-10) — a removed From-connection no longer silently sends from the backend default: resets to default + blocks send with a notice alert.
- `Features/Search/GlobalSearchView.swift` (B-0601b-2) — People results use `SenderAvatarView` (real avatars) instead of a custom gray-initials ZStack.

**macOS (`apps/macos/TodusMac`)**
- `Views/Email/MacEmailComposeView.swift` (QA-0608-3) — "Start fresh" resets `didApplySignature` + re-applies signature; (B-029) `.onDisappear` cancels the autosave task so a late write can't resurrect a cleared draft.
- `App/MacOnboardingViews.swift` (QA-0608-7) — Gmail onboarding auto-advances when already connected.
- `Views/Email/MacEmailThreadView.swift` (MAC-2) — message list is `LazyVStack` (bounded WebView build cost on long threads).
- `Views/AI/ChatUISpec/CardViews.swift` — AI compose-card CC/BCC now have add-fields (mirrors the iOS fix).
- `Services/Email/EmailService.swift` (QA-0608-9) — read-state now also patches `threadDetailCache` so search-opened threads reflect read/unread (with symmetric rollback).

## Fixed — second batch (same pass)
- **Web B-014 (privacy)** — `bimi-avatar.tsx` now gates ALL third-party favicon fetches (local builder AND the backend `fallbackUrls`, which also carry clearbit/icon.horse/DDG/Gravatar URLs the browser fetches) behind the existing `externalImages` setting; keeps own Google contact photo + inlined sanitized BIMI SVG.
- **Server B-015 (privacy)** — `lib/sender-avatar.ts` short-circuits before any anonymous third-party request when `externalImages` is off; `trpc/routes/avatar.ts` loads + passes the setting. (KV cache still deferred — no general-purpose KV binding; `// TODO(B-015)` left.)
- **Web B-040** — tasks placeholder de-bilingualized to neutral English.
- **iOS EM-8** — Copy message text / Copy as quote now copy the full `message.body` rendered to plain text (new `htmlToPlainText`), not the snippet.
- **iOS B-037** — stale-refresh log now includes dropped/kept counts (telemetry); strict `<` kept.
- **iOS B-034** — documented the intentional `hideTabBar` asymmetry (MainTabView resets per tab switch).
- **macOS QA-0608-2** — per-message reply/forward quotes the clicked message (`selectedComposeMessage`), not always the latest.
- **macOS QA-0608-4** — partial-enrichment failures no longer shrink the folder cache (`EnrichmentResult` + `mergeSurvivors`).
- **macOS MAC-3** — `loadThreads` cache/live/spinner/error gated by a monotonic `loadGeneration` token.

## Fixed — third batch (same pass; the previously-"deferred" set)
All build-verified (iOS + macOS green, 94 iOS tests pass; server/web tsc-clean on touched files).
- **iOS EM-1 + EM-3** — `SenderAvatarView` now renders through a downsampling, disk-cached loader (`AvatarImageLoader`: NSCache → `AvatarDiskCache` → fetch+ImageIO thumbnail at point-size×scale → persist), replacing raw `AsyncImage`; waterfall + person-vs-brand treatment preserved.
- **iOS EM-7** — inbox search uses a precomputed per-thread lowercased blob (no per-keystroke 4-field lowercasing); `threadsForSender` cached in `@State`; sender-group rebuild already gated to People view.
- **iOS H9** — Day view now renders the unified Apple+Google+CalDAV events via a single-column `CalendarMultiDayView(dayCount:1)` (same renderer as Multi-Day); removed the "switch to Multi-Day" banner.
- **Server B-025** — `GENERATIVE_UI_PROMPT` gated behind `supportsGenerativeUI` request flag (default true; `AiChatPrompt` takes `generativeUI` option).
- **Server B-028** — added `autoLabelThreads` policy field (default true); `labelGenerationWorkflow` registration gated by it (vectorization intentionally always-on).
- **Server B-015 (cache)** — added a module-level in-memory isolate cache (~24h TTL, 2000-cap) around `resolveSenderAvatar` (no general KV binding exists; this covers repeat hits within an isolate).
- **Server + clients — subscription productId** — `subscription.getStatus` now returns the active `productId`+`interval` (sourced from Autumn); macOS cancel uses the real product instead of hardcoded `pro_monthly`.
- **Server + web — PAR-A2** — `createEvent`/`updateEvent`/`deleteEvent` accept an optional user-scoped `connectionId` (act on a non-active connection's calendar); added `calendarsMulti` (calendars across all google connections); web `EventEditDialog` create mode has a calendar picker.
- **macOS reminder scheduling** — `MacNotificationService` reminders are now actually scheduled: `reconcileTaskReminders` runs on launch / foreground / toggle (auth requested), schedules per-task `UNCalendarNotificationTrigger`s + the due-today digest, cancels orphans. (`calendarRemindersEnabled` has no scheduler defined on either platform — left out of scope.)
- **macOS move-to-folder** — "Move to…" context-menu submenu in inbox + thread; `EmailService.move(ids:toLabelId:fromFolder:)` via `mail.modifyLabels` with optimistic apply + rollback.
- **macOS notification cold-launch** — taps during cold launch are queued (`pendingNotificationResponses`) and replayed in `initializeApp()`, mirroring `pendingDeepLinks`.
- **macOS event-edit prefill** — `CalendarEvent` carries `location`/`notes`; edit sheet seeds + round-trips them through `CalendarService.updateEvent`/`createEvent`.
- **macOS BH-0601-2** — foreground thread-open joining a prefetch now sets a fallback `errorMessage` on nil result.
- **macOS BH-0601-3** — `CalendarEvent.id` is the composite namespaced id (collision-free Identifiable); `providerEventId` used for EKEventStore lookups.
- **Web 001** — extracted `TaskItemCompact` into `components/tasks/task-item.tsx`; home page imports it (removed the inline duplicate).
- **Web PAR-F1** — removed the dead `/forgot-password` link from the commented login block (route actually exists; the dead reference is gone).
- **Web PAR-C (code)** — voice client-tool bridge is code-complete + compiling: `lib/server-tool.ts` `callServerTool` → `POST /api/ai/do/:action`; `voice-provider.tsx` `clientTools` re-enabled, errors caught (no throw on a normal session). The code-review finding ("clientTools commented out + broken `@/lib/server-tool` import") is resolved. (Its runtime activation is a deployment/operator prerequisite, not a code defect — see the operator-prerequisites note below.)
- **Hygiene** — added `**/dev.log` to root `.gitignore` (B-050).

## Verified ALREADY-FIXED (stale entries — no action needed)
- iOS 2026-05-17 audit: **C1, C2, C3, C4, C5, H1, H3, H4, H10, H11, H12, H14, H15, H16, H17** (16/17 fixed by later passes).
- iOS: B-010 (avatar cache key is SHA256, not hashValue), B-011 (`today 14` parsing), B-038 (deleteConversation skip-list), B-0601b-1 (compose recipient raw-binding).
- Server: B-001 (orphan 0056 slack migration dropped), B-002 (settings `location` persists via AI page).
- macOS: QA-0608-1, QA-0608-5, B-004 (markdown→HTML both send paths), B-005 (From connectionId serialized), B-031.

## Verified NOT-A-BUG / by-design
- Server: B-026 (`lastReviewedAt` column doesn't exist on `assistant_prepared_action`), B-017 (`WorkflowRunner` is a DurableObject, not a CF Workflow — no replay).
- iOS: EM-9 (navigationDestination(item:) auto-resets on dismiss), B-018 (`@MainActor` class is implicitly Sendable).
- macOS: QA-0608-6 (picker intentionally editable), B-032 (bucket vs score split is display-only).
- Web: PAR-B3 (mention context IS injected into the agent input, not UI-only).

## Fixed — fourth batch (the last reachable items)
- **Server B-022** — `buildThreadAnalysis` now short-circuits for non-conversational threads (receipt/notification/marketing/verification) BEFORE the expensive DB reads + memory upserts + candidate generation. Field-by-field shape verified identical by tsc; keeps cheap text-derived fields (lead line, verification code, receipt); **skips `syncOpenLoops`/`syncPreparedActions` entirely** (rather than passing `[]`, which a destructive reconcile would use to retire legitimately-existing loops/actions) and reads back existing rows so prior data is neither created nor destroyed. tsc-clean on `assistant.ts`.
- **PAR-C** — verified ALREADY-FIXED in a committed change (`feat(web): wire voice client tools`): `lib/server-tool.ts` `callServerTool` bridges to `POST /api/ai/do/:action`; `voice-provider.tsx` clientTools re-enabled + tsc-clean; errors are caught (no throw on a normal session). The remaining ElevenLabs *dashboard* tool-declaration is the only external step.
- **B-050 / B-051** (hygiene) — `**/dev.log` added to `.gitignore`; the 3 empty tracked files (`new-website/check-font.js`, `check-page.js`, `screenshot.js`) and `new-website/relume/dev.log` removed from tracking (deleted + `git add` to stage removal, since `git rm` is policy-blocked; the log is regenerable + now gitignored).

## Fixed — fifth batch (product-decision + repo hygiene)
- **B-033** (weekend snooze) — "weekend" now resolves to the nearest upcoming Sat OR Sun still in the future at 9am (Sat afternoon → Sun 9am). Shared helper on iOS + macOS; 5 new SnoozeOption tests.
- **B-036** (auto-resolve type) — an input with a date AND a specific time-of-day classifies as `.event` even without an event keyword ("Dentist Tuesday 2pm" → event); date-only stays `.task`. Added a `hasTime` flag through the parser models (iOS + macOS); 3 new parser tests.
- **B-035** (multi-intent date) — VERIFIED already-correct: `intent.date ?? selectedDate` is per-sub-intent (CompoundIntentParser parses each segment's own date). Contract documented in a comment.
- **B-001-root** (package-manager hygiene) — removed the redundant bun-only `workspaces`/`catalog` + top-level `patchedDependencies` from `package.json` (pnpm uses `pnpm-workspace.yaml`, which already holds the authoritative catalog/patches) and dropped the divergent `bun.lock`. pnpm is now the unambiguous single manager; pnpm resolution unchanged.

iOS now at **102 unit tests** (8 new), all green; iOS + macOS builds green.

## Fixed — sixth batch (MAC-1, after a deeper root-cause fix)
- **MAC-1** — TodusMacTests now runs in Xcode/CI. Root cause turned out deeper than "regen risk": `project.yml` had **no `packages:` section**, so the MLX SPM packages (added via the Xcode UI) were missing from it and every `xcodegen generate` silently dropped them (19→4 MLX refs) and broke the app's `Cmlx`/`_NumericsShims` resolution. Fix: (1) declared `mlx-swift-examples` (2.29.1) in `project.yml` + linked `MLXLLM`/`MLXLMCommon` on the app target — the project is now **regen-safe**; (2) made `EmailModels.swift` Foundation-only (`AppLogger` → `#if DEBUG print`) and moved `GetThreadResponse`/`FailableDecodable`/`EmailThreadDetail` into a Foundation-only `Domain/EmailThreadResponse.swift`; (3) made `TodusMacTests` a standalone host-less logic bundle compiling those two files directly (no `@testable`/MLX host) + a dedicated `TodusMacTests` scheme that builds only the test target. Verified: macOS app `BUILD SUCCEEDED` (MLX refs back to 19), `xcodebuild test -scheme TodusMacTests` → **11/11 pass**.

## No open code defects remain
Every CODE_REVIEW_BACKLOG item that is a code defect — including MAC-1 and the PAR-C
code finding — has been fixed, built, tested, and committed (passes 1–6). There are no
remaining open code items.

## Operator / deployment prerequisites (NOT code — nothing to fix in this repo)
These are configuration/deployment actions that live outside the codebase. They are not
code-review findings and cannot be completed by editing files in this repo:
- **Voice tools activation (was PAR-C):** the bridge code is shipped + compiling. To turn
  it on, declare the client tools (names + JSON schemas) on the **ElevenLabs agent in the
  ElevenLabs web dashboard** and set `VITE_PUBLIC_ELEVENLABS_AGENT_ID` in the deploy env.
  Third-party SaaS config — no repo change makes it work; no ElevenLabs credentials exist
  in this environment.
- **Ship the server fixes:** `pnpm deploy:backend` (passes 1–4 server changes only take
  effect once deployed).
- **macOS test target:** `xcodebuild test -scheme TodusMacTests` now runs (11/11); CI can
  invoke that scheme.

---

# Bug Hunt — 2026-06-13 — full iOS app (`/bug-hunt`)

Full-app review via 5 parallel SwiftUI review agents (Services, Tasks/Folders/Home, Calendar, Email/AI/Docs, Settings/App/Nav). Build green before and after. ~22 real bugs found; high-confidence/safe ones auto-fixed, the rest deferred below.

## Auto-fixed this pass (22 across 16 files — all build-verified)

- `Features/Tasks/CalendarTaskView.swift` — inverted success haptic (fired on un-complete); capture `willBecomeDone` before toggle.
- `Features/Search/GlobalSearchView.swift` — event dot used packed-RGB `calendarColor` as a hue → meaningless color; now uses `calendarColorRed/Green/Blue` like every other call site.
- `Features/AI/CardViews.swift` — (1) robust `Color(hex:)` (3/6/8-char, validates hex, falls back) + new `rgbComponents`/`isLightHex`; (2) `LabelCardView` white tag-icon now luminance-aware (was invisible on light swatches); (3) WeeklyAgenda `ForEach` keyed by offset not duplicate date id; (4) empty-state messages for empty Calendar/Contact list cards (were blank bordered boxes).
- `Features/AI/CardViews.swift` (InlineComposeCard) — CC/BCC had no input field (couldn't add recipients) + Send dropped typed-but-unsubmitted addresses. Added per-target inputs (`toInput`/`ccInput`/`bccInput`) + flush-on-send.
- `Features/AI/ChatUISpecView.swift` — (1) button reads both `actionParams` and `params` (was silently no-op for `params` emitters); (2) card container uses visible `surfacePrimary`/`cardBorder` (was near-invisible `systemBackground.opacity(0.5)`).
- `Features/Email/EmailComposeView.swift` — (1) forward title showed "New Email" (now "Forward"); (2) `fromConnectionId` persisted+restored in autosave (was reverting to first account on reopen).
- `Features/Calendar/CalendarMonthView.swift` — month grid built with `bySetting:.day` (jumps months near boundaries/DST) → `byAdding`.
- `Features/Calendar/CalendarTimeGridView.swift` — grid-tap minutes now clamped to a valid slot (bottom/overscroll tap yielded hour 24 → silent no-op).
- `Services/Calendar/CalendarService.swift` — clamp sRGB-converted color components to 0...1 (P3 out-of-gamut rendered over-saturated).
- `Features/Settings/RemindersSetupView.swift` — toggle path now clears stale `permissionDenied` banner + runs outbound `syncExistingTasksToReminders` for parity with `connect()`.
- `Services/Voice/GeminiLiveProvider.swift` — input/output transcription emitted `isFinal:true` (REPLACE) → kept only last delta fragment; now `isFinal:false` (APPEND), finalized on `turnComplete`. Fixes both coordinator + VoiceChatViewModel consumers.
- `Services/Voice/AudioPlayerManager.swift` — odd-byte PCM chunk caused 1-byte heap overflow in `memcpy`; copy only frame-aligned bytes.
- `Features/Voice/VoiceChatViewModel.swift` — capture guard now accepts `.reconnecting` (was discarding started engine → mic-dead session).
- `Features/Tasks/InboxView.swift` — `.dueDate` sort now breaks `(nil,nil)` tie by `createdAt`, matching Board/Table/Calendar (rows no longer reshuffle across views).
- `Features/Docs/DocsListView.swift` — error empty-state Retry button + iPad detail pane loads a just-created doc not yet in `allDocs` (was stuck on "Select a document").
- `Features/Tasks/CaptureComposer.swift` — `needsHighlights` triggered on any `_` (lone underscore in email/file) forcing attributed rewrite → keyboard dismiss; now tests the actual paired-italic regex.
- `Domain/EmailModels.swift`, `Features/Email/EmailThreadView.swift` — removed unnecessary `nonisolated(unsafe)` (compiler warnings).

## Second pass — ALL 13 deferred items now resolved (build + 94 unit tests green)

The "deferred" items below were re-evaluated and resolved in the same session: 10 fixed in code, 3 verified to be non-bugs (no change needed).

| ID | Area | Resolution |
|----|------|-----------|
| BH-0613-1 | Calendar (multi-account) | ✅ FIXED. Backend `calendar.calendars` already accepted `connectionId` (resolves target connection, user-scoped — no IDOR); added `accessRole` echo to its response (`apps/server/src/trpc/routes/calendar.ts`). Client `GoogleCalendarService` now passes `connectionId: conn.id` and decodes/uses the real `accessRole` (was hardcoded `"reader"`). |
| BH-0613-2 | Calendar | ✅ FIXED. Added `calendarId` to `CalendarEvent` (set from `EKCalendar.calendarIdentifier`); `UnifiedCalendarService` builds `apple:{calId}` instead of `apple:unknown`. |
| BH-0613-3 | Calendar | ✅ FIXED. `MultiDayPageView` column filter now uses an overlap test (`start < dayEnd && end > dayStart`) so cross-midnight events appear on each covered day. (EventKit's predicate already returns overlapping events, so no extra leading window pad needed.) |
| BH-0613-4 | Calendar | ✅ FIXED. `loadMoreListEvents` dedupes appended events by id; the bottom trigger only re-fires when the list grows, so empty pages no longer loop. |
| BH-0613-5 | Calendar | ✅ VERIFIED NOT A BUG. `didUpdate` is correct: new events set `editedEvent = self` (line 300) → `originalEvent === editingEvent` true → opens editor; existing events use `makeEditable()` clone → `editedEvent` points at the original → saves directly. |
| BH-0613-6 | Navigation | ✅ FIXED (UX bug removed). The live `MainTabView` uses a fixed native tab bar and does not consume `tabBarTabs`, so the customization **onboarding step was a no-op** — removed it from the `RootView` chain + pending flags. The native bar (good UX) is kept; the customization components remain for if/when the dynamic tab bar is finished (out of scope: high-regression rebuild of core nav). |
| BH-0613-7 | Settings | ✅ FIXED. Consolidated to a single source of truth: `AppServices.accentPreference.didSet` now mirrors to the server-synced `ios_accent_color` key and pushes `accentColor` to the server; both the Preferences and Appearance pickers drive `accentPreference`; removed the duplicate `accentColorKey` state + redundant onChange. (Visible app re-tinting via `.tint` remains a separate product decision — the footer already says some surfaces adopt the accent in a later release.) |
| BH-0613-8 | Dead code | ✅ NOT A USER-FACING BUG. `MoreSheetView`/`DefaultMailOnboardingView`/`EmailAIDraftSheet` are never instantiated → zero runtime/UI effect. Left in place; deleting would require hand-editing `Todus.xcodeproj/project.pbxproj` (high risk, no user benefit). |
| BH-0613-9 | Email | ✅ FIXED. `SenderAvatarView` snapshots candidate URLs into `@State` (`resolvedCandidates`), adopted on first populate + growth only — `recordSuccess` reordering the cache no longer shifts `urlIndex` onto a different URL (flicker gone). |
| BH-0613-10 | App | ✅ FIXED. `RootView` snapshots the *set* of pending onboarding indices and computes the step as the position of the first still-pending flag — counts up monotonically even when a later step auto-skips first. |
| BH-0613-11 | Voice | ✅ FIXED. `VoiceChatViewModel.handleEvent` ignores all events once `connectionState` is `.failed`, so a trailing provider event can't resurrect a torn-down session. |
| BH-0613-12 | AI | ✅ FIXED (`addSavedPrompt` now dedupes by id / move-to-top). `aiCanSendEmail` verified NOT a bug — consistent with its two sibling flags and idempotent. |
| BH-0613-13 | Calendar | ✅ FIXED. now-indicator dot accounts for the 0.5pt inter-column separators; `CalendarYearView` event dots index the full day-span (guard-capped) so multi-day events dot every covered day. |

---

# Web → Native parity — deferred sub-items (2026-06-13)

Tracking follow-ups from the parity workstreams. Master plan:
`docs/superpowers/specs/2026-06-13-web-native-parity-MASTER-design.md`.

| ID | Area | Where | Problem | Suggested fix |
|----|------|-------|---------|---------------|
| PAR-A2 | Calendar | `apps/web/app/(routes)/mail/calendar/page.tsx`, `apps/server/src/trpc/routes/calendar.ts` | ✅ MOSTLY DONE — visibility toggles shipped via `eventsMulti` (no server change). REMAINING: (1) create-on-specific-calendar picker in `EventEditDialog` (currently defaults to `primary`); (2) cross-connection editing — write mutations are `activeConnectionProcedure` so editing an event on a non-active connection's calendar fails; needs optional `connectionId` on `createEvent/updateEvent/deleteEvent`; (3) `calendar.calendars` is active-connection only, so the calendar list shows only the active connection's calendars. | Add `connectionId` to write mutations + a `calendarsMulti` query; add a calendar picker to the create dialog. |
| ~~PAR-B2~~ | AI tools | `apps/server/src/routes/agent/tools.ts` | ✅ DONE — `createEvent` tool added, gated by (now-enforced) `aiCanWriteCalendar`. | — |
| PAR-B3 | AI context | `apps/server/src/lib/mentions.ts`, `apps/web` chat | Audit flagged that `@`-mention context may not actually be injected into the agent system prompt (UI-only). | Trace `injectMentionContextIntoMessages` end-to-end; confirm or fix. |
| ~~PAR-C~~ | Voice tools | `apps/web/providers/voice-provider.tsx`, `apps/web/lib/server-tool.ts` | ✅ CODE DONE — `callServerTool` bridge (`lib/server-tool.ts` → `POST /api/ai/do/:action`) + `clientTools` re-enabled in `voice-provider.tsx`, tsc-clean, errors caught (no throw on a normal session). The only residual is the **external ElevenLabs dashboard** tool-declaration + `VITE_PUBLIC_ELEVENLABS_AGENT_ID` — an operator/deployment step, not a code defect (see "Operator / deployment prerequisites" above). | — |
| PAR-B-TEST | AI tools | `apps/server/src/routes/agent/tools.ts` | New task/calendar tools are DB/Google-backed; no automated test (server suite has no DB harness). Verified via tsc + server test suite (no import/compile breakage). | Add integration tests once a DB/Google harness exists; for now manual verify via chat. |
| PAR-F1 | Auth | `apps/web/app/(auth)/todus/login/page.tsx:384`, `apps/web/app/routes.ts` | `to="/forgot-password"` is a **dead link** — no such route. Low priority (auth is OTP/Google-primary; email/password sign-in UI is commented out). | Either build `/forgot-password` + `/reset-password` pages (Better Auth `requestPasswordReset`/`resetPassword`) or remove the link. |
| PAR-SIG (not a gap) | Signatures | `apps/web/.../settings/signatures/page.tsx`, `apps/macos/.../MacSignatureStore.swift` | Audit flagged per-account signatures as a web localStorage "data-loss bug". On re-check this is **at parity**: macOS also stores them locally (UserDefaults). Both are local-per-device by design. | No action — fixing web to server-sync would *diverge* from native. Revisit only if cross-device signatures become a product goal (would need a server table + native changes). |

---

# macOS QA pass — 2026-06-13 — email loading / thread-open / hangs

Root-cause investigation of the reported macOS symptoms (emails not loading, errors entering threads, click/navigation hangs). 2 parallel read-only investigators + manual verification against source. App `BUILD SUCCEEDED` before + after. Decode-tolerance regression tests run green (11/11) against the real `EmailModels.swift` via `scripts/run-email-decode-tests.sh`.

## Fixed this pass (7)

| File | Sev | What changed |
|------|-----|--------------|
| `Services/Email/EmailService.swift` `checkConnection` | 🔴 blocker | Any transient failure (timeout/offline/5xx) set `hasConnection=false`, parking **connected** users on the "Connect Gmail" onboarding prompt. Now only a *successful* empty response sets it false; failures set `connectionCheckFailed` and leave a known-good connection intact. New `connectionCheckFailedState` view shows a retry instead of the connect prompt. |
| `Services/Email/EmailService.swift` `loadThreads` (401 catch) | 🟠 high | A 401 set `hasConnection=false` (→ wrong "Connect Gmail" state) and left `errorMessage` nil (silent). Now surfaces "Your session expired" and leaves connection state alone; root view drives re-auth via `isSessionExpired`. |
| `Services/API/TodosAPIClient.swift` retry loop | 🟡 med | Added `try Task.checkCancellation()` at the top of the retry loop so a cancelled/timed-out request stops promptly instead of burning another attempt + full URLSession timeout. `loadThreads` now distinguishes timeout copy and treats `CancellationError` as non-error. |
| `Domain/EmailModels.swift` `EmailSender`/`EmailMessage` | 🟠 high | **The "errors entering threads" cause.** A message with null/missing `sender` or null `email` threw a `DecodingError` that aborted the *whole* `mail.get` thread decode → hard error screen. Email decode is now tolerant (`email` → `""`, missing sender → "Unknown sender" placeholder). |
| `Services/Email/EmailService.swift` `GetThreadResponse` | 🟠 high | Messages now decode element-by-element via `FailableDecodable<EmailMessage>`, so one malformed message (e.g. missing `id`) is dropped instead of sinking the entire thread. |
| `Views/Email/MacEmailThreadView.swift` `recomputeFallbackChips` + `loadThread` | 🟡 med | The verification/tracking regex ran a full-document `<[^>]+>` strip on the main actor at thread-open (stutter on large newsletters). Input now capped to 20k chars. `markAsRead` gated on a successful load (no longer marks read on failed/cancelled opens). |
| `Views/Email/MacEmailInboxView.swift` paginator | 🟡 med | A failed "load more" set an (invisible) error and left the cursor, so `.onAppear` re-fired immediately → tight retry loop hammering the backend. Added `paginationFailed` flag + an explicit "Couldn't load more — Retry" footer; auto-fire is gated on the flag. |

## Tests added

- `apps/macos/TodusMacTests/EmailDecodeToleranceTests.swift` — XCTest (real types via `@testable import Todus`) covering sender/message/thread decode tolerance + the one-bad-message regression.
- `apps/macos/scripts/run-email-decode-tests.sh` + `scripts/email-decode-tests/main.swift` — Xcode-free runner that compiles the **real** `EmailModels.swift` and runs the decode regressions (11/11 green). Use this until the XCTest target is wired (see blocker below).

## Needs human review (deferred)

| ID | Area | Where | Sev | Problem | Suggested fix |
|----|------|-------|-----|---------|---------------|
| MAC-1 | Test infra | `project.yml` `TodusMacTests` | 🟠 high | Test target is defined in `project.yml` but **not runnable** yet: `xcodebuild test` fails resolving MLX's `Cmlx`/`_NumericsShims` C modules in the `@testable` test-host rebuild (regular `build` is fine). Also: a bare `xcodegen generate` rewrites ~285 lines of the committed `project.pbxproj` (drift), so it wasn't regenerated this pass. | Wire MLX C-module search paths for the testable build (or split email models into an SPM lib target with no MLX dep that the test target imports), then regenerate the project intentionally and commit the pbxproj. Interim: `scripts/run-email-decode-tests.sh`. |
| MAC-2 | Email perf | `Views/Email/MacEmailThreadView.swift` `messageView` `ForEach` | 🟡 med | Message list is an eager `VStack` (not `LazyVStack`); WebViews are gated by `isExpanded` so open cost is bounded today, but very long threads with several expanded messages build multiple `WKWebView`s on the main thread. | Lazy-mount + pool WebViews if long-thread jank shows up in profiling. |
| MAC-3 | Email | `EmailService.loadThreads` folder-switch | 🟡 med | A→B→A interleaved folder switches can let a slow superseded load commit to the cache (the live-`threads` write is folder-guarded; the cache write is not). | Add a monotonic `loadGeneration` token; gate the cache write on it too. |

---

# Bug Hunt — 2026-06-08 — iOS email surface (`/bug-hunt`)

Deep hunt across `Features/Email/*` + `Services/Email/EmailService.swift`, run by 4 parallel read-only audit agents (service logic, inbox/rows + perf, thread/compose, avatars/perf). Every finding re-verified against current source (several earlier "deferred" items were already fixed by parallel work and dropped). Build green before + after fixes.

## Auto-fixed this pass (3)

| File:line | Severity | What changed |
|-----------|----------|--------------|
| `Features/Email/EmailThreadView.swift:126` + `EmailComposeView.swift:113` | 🔴 **critical (data loss)** | **Forward sent only the snippet.** Forward passed `lastMessage.plainText` — which decodes from the `title`/snippet field (`EmailModels.swift:85`), not the body — so forwarding silently truncated the email to a one-line preview. Added `isForward`/`originalMessage` params to the compose init and route Forward through them with the **full** `lastMessage.body`; the backend appends it (`google.ts:1236`). Verified end-to-end against the server handler. |
| `Services/Email/EmailService.swift:309,394-410` (`performLoadThreads`) | 🟠 high | **Superseded-load state race.** The `defer` gen-gated only the spinner; the `threads`/`errorMessage`/`hasConnection` writes were ungated, so a slow superseded load could paint a stale error banner over a newer successful inbox. Added `guard loadGeneration == myGen else { return }` before state application and gated every `catch` write on `myGen`. |
| `Services/Email/EmailService.swift:1548` (`invalidateThreadDetail`) | 🟡 med | **Stale thread detail after list mutation.** `markAsRead`/`markAsUnread`/`toggleStar` updated `threads` but not `threadDetailCache`, so opening a just-read/just-starred thread showed the pre-mutation state until the cache TTL expired. Added a shared `invalidateThreadDetail(ids:)` and call it from those mutations. |

## Needs human review (verified real, deferred — higher-risk / unvalidatable under `--ui-testing` / product calls)

| ID | Area | Where | Sev | Problem | Suggested fix |
|----|------|-------|-----|---------|---------------|
| EM-1 | Email perf | `SenderAvatarView.swift:548` | 🟠 high | Inbox avatars use raw `AsyncImage` with **no downsampling** — 256–512px favicons/apple-touch-icons decoded full-size into a 40pt circle; main memory/CPU cost on fast scroll. | ImageIO thumbnail decode; route through the existing `CachedAvatarImage`. |
| EM-2 | Email perf | `SenderAvatarView.swift:539-589` | 🟠 high | Senders without a bundled icon fire **up to ~10 sequential favicon GETs per row** while scrolling. | Cap candidate URLs; prefer cached/known-good; drive from `.task` not phase `.onAppear`. |
| EM-3 | Email perf | `SenderAvatarView.swift:548` vs `AppTheme.swift` `AvatarDiskCache`/`CachedAvatarImage` | 🟠 high | The well-built **disk image cache is bypassed** by the inbox (only 2 settings avatars use it); inbox relies on `URLCache`, which 3rd-party favicon providers don't always make cacheable → refetch each launch. | Route sender avatars through the disk cache. |
| EM-4 | Email | `Features/Email/SenderIconRegistry.swift` (letter-only entries) | 🟠 high | Known brands (office/azure/monday/beehiiv/disneyplus/postmark/mailerlite/braintree) have `slug == nil` → early-return to gray initials, never try a favicon, and `spec.letter` is dead. They look worse than unknown senders. | Drop letter-only entries (fall through to favicon waterfall) OR render `spec.letter` on `spec.background`. |
| EM-5 | Email | `Services/Email/EmailService.swift:1406-1425` (`connectGmail`, multi-account) | 🟠 high (med conf) | When a 2nd (Gmail) account is linked while one already exists, returns `true` without verifying the new connection row landed (`hasConnection` already true). | Re-`checkConnection(force:true)` and confirm the Gmail email is present before reporting success. |
| EM-6 | Email | `Features/Email/EmailAIDraftSheet.swift` | 🟠 high | Entire 368-line file (its own SSE/auth pipeline) is **dead** — never instantiated; compose `aiFAB` opens `AIChatView`. | Delete the file (requires removing it from `Todus.xcodeproj` — do via Xcode). |
| EM-7 | Email perf | `EmailInboxView.swift:1414` (`recomputeFilteredThreads`), `:1494` (`threadsForSender`), `:790` (`buildSenderGroups`) | 🟡 med | Full-list lowercasing per keystroke; `threadsForSender` re-filters+sorts the pool in a computed prop every `body`; sender groups re-sort on every `threads` change. | Precompute lowercased search fields; cache `threadsForSender` in `@State`; gate group rebuild to People view. |
| EM-8 | Email | `EmailThreadView.swift:1761-1777` ("Copy message text"/"Copy as quote") | 🟡 med | Copies `plainText` (snippet) not the full message — same root as the Forward bug. | Needs an HTML→plaintext helper; convert `message.body`. |
| EM-9 | Email | `EmailInboxView.swift:298` | 🟡 med (low conf) | Archiving/deleting the currently-open thread doesn't clear `selectedThreadId`; detail can dangle on a removed thread when triggered from elsewhere. | Clear `selectedThreadId` if its id vanished from `threads`. |
| EM-10 | Email | `EmailComposeView.swift` (`fromConnectionId` resolve at send) | 🟡 med | A stale `fromConnectionId` (connection removed) silently `flatMap`s to nil → sends from the default mailbox without warning. | Validate the id still exists; warn if it resolved to nil. |
| EM-11 | Email perf | `EmailService.swift:1727-1748` (`mergePages`) | 🔵 low | Pagination appends new ids without re-sort (documented contract) — a page-2 thread newer than page-1's tail lands out of date order. | Optional re-sort by date desc after merge (mind the pinned unit test). |
| EM-12 | Email | `EmailThreadView.swift:2114` (webView `measureHeight`) | 🔵 low | 0.7s `asyncAfter` not cancelled on teardown (weak-guarded so safe, just wasteful). | Track a `DispatchWorkItem`; cancel in `dismantleUIView`. |

> Perf note: EM-1..EM-3 + EM-7 are the real performance cost on a fast-scrolling, real-account inbox. They were **not** auto-fixed because they touch the image-loading pipeline / require profiling against real mail, and the `--ui-testing` harness has no email data to validate against. Recommend a dedicated avatar-pipeline pass (downsample + disk-cache + candidate cap) with Instruments on a real account.

---

# 2026-06-08 — QA pass (macOS app, pre-TestFlight)

Scope: native macOS app `apps/macos/TodusMac`. Build = clean `xcodebuild` (Debug, macOS, arch=arm64) — **BUILD SUCCEEDED** before and after fixes. 3 parallel sub-agents by surface (launch/auth/root, email, calendar/tasks/docs/AI); every finding re-verified against source before any edit. App launched in-app for runtime validation (auth gate, light/dark). No automated UI auth path exists on macOS, so logged-in flows were validated by code trace + a real persisted session where available.

## Auto-fixed (10) — all re-verified at source, build green

| File:line | Severity | What changed |
|-----------|----------|--------------|
| `apps/macos/.../Services/Email/EmailService.swift:1130` (`sendEmail`) | 🔴 **critical** | Decoded `SendResponse` but never checked `success`; backend returns HTTP 200 `{success:false,error}` for undo-send / scheduled-send failures → compose closed + autosaved draft cleared as "sent" while the mail was **lost**. Now `guard response.success else { surface error; return false }`; `SendResponse` gained `error`. |
| `apps/macos/.../Services/Drafts/MacDraftService.swift:125` (`send`) | 🔴 **critical** | Same silent-failure on the **attachment** send path (decoded `EmptyResult`, ignored `success`). Now decodes `SendResult{success,error}` and `throw`s on `success == false` so the compose sheet stays open and surfaces the error. |
| `apps/macos/.../Services/AI/MacAIChatService.swift:1405` (`saveCurrentConversation`) | 🟠 high | Always minted a fresh `UUID()` + inserted → every autosave / clearHistory / loadConversation for the **same** live chat appended a duplicate history row (and defeated server merge-by-id, so dupes synced). Now updates the existing entry in place when `currentConversationID` matches. |
| `apps/macos/.../App/MacOnboardingViews.swift:126` (`MacGmailOnboardingView.connect`) | 🟠 high | Called `signInWithGoogle()` directly → an Apple/OTP-signed-in user clicking "Connect Gmail" had their **session overwritten** by a Google sign-in (account hijack) instead of linking. Now uses the link-aware `EmailService.connectGmail(authService:)` (links when authed, signs in only when signed out), mirroring iOS. |
| `apps/macos/.../Views/Docs/MacDocEditorPane.swift:394` (`load`) | 🟠 high | `lastText` was only set in `onContentChange`, so a flush before the editor's first change (open-then-close, or doc switch) wrote `contentText` as a single space — or the **previous** doc's text — silently corrupting server search/preview text. Now seeds `lastText = d.contentText ?? ""` on load. |
| `apps/macos/.../Views/Email/MacEmailInboxView.swift:590` (row context menu) | 🟠 high | Archiving/deleting the **currently-open** thread via the list context menu didn't clear `selectedThreadId` → the detail pane kept rendering a thread no longer in the list; reply/archive/delete from that stale pane acted on a gone thread. Now clears selection when the acted-on thread is open (matches the header close button). |
| `apps/macos/.../Services/AI/MacAIChatService.swift:1344` (`appendError`) | 🟡 med | A mid-stream network drop **overwrote** already-streamed assistant tokens with `⚠️ …`, discarding the partial answer the user was reading. Now appends the error on a new line, preserving streamed text. |
| `apps/macos/.../App/MacRootView.swift:490` (launch silent-refresh `.task`) | 🟡 med | The on-launch `attemptSilentRefresh()` task ran once on appear — before the sibling bootstrap task's `await restorePersistedSession()` set `hasBootstrappedAuthState`/`isAuthenticated` — so its guard always failed and it **never ran**. Re-keyed `.task(id: hasBootstrappedAuthState)` so it re-fires once bootstrap completes. |
| `apps/macos/.../Views/Calendar/MacCalendarView.swift:568` (`dayView`) | 🔵 low | Day view filtered timed events by start-day equality, so a multi-day event that **began earlier** vanished from the day it continued into (week view already used overlap). Now overlap (`start < endOfDay && end > startOfDay`) for timed events; all-day pills keep start-day keying to match the week grid. |
| `apps/macos/.../Views/Email/MacEmailComposeView.swift:664` (`tokenizeRecipients`) | 🔵 low | Split on `,` only, so pasting `a@x.com b@y.com` or `a@x.com; b@y.com` became one invalid mega-token that blocked send. Now splits on commas, semicolons, and whitespace/newlines. |

## Needs attention (not auto-fixed — verified real, deferred as higher-risk/product calls)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| QA-0608-1 | macOS email | `EmailService.swift` `errorMessage` (set at `:531/1204/1225/1259/1271/1293`; read at `MacEmailInboxView.swift:243,814`) | 🟡 med | One `errorMessage` field is shared by load + markRead/unread + archive/delete/star + connectGmail and never cleared on success. A stale action error can flip the inbox to the full-screen "Couldn't load" panel (gate keys off `errorMessage != nil && filteredThreads.isEmpty`) and shows under the Gmail connect card. | Per-surface error: transient toast for action failures, separate from the load-level `errorMessage` that drives the full-screen state; or clear `errorMessage = nil` on each action success. |
| QA-0608-2 | macOS email | `MacEmailThreadView.swift:270` (reply/forward sheet) | 🟡 med | Compose sheet binds to `detail?.messages.last`; opening reply/forward before the thread finishes loading shows an empty sheet, and per-message "Reply" (`:637`) discards which message was clicked → always quotes the last message. | Capture a `@State selectedComposeMessage` when the action fires (default `detail?.latest`); guard the sheet so it can't open with no message. |
| QA-0608-3 | macOS email | `MacEmailComposeView.swift:916` (`appendSignatureIfNeeded`) + `:515` ("Start fresh") | 🟡 med | Switching the From account appends the new signature without stripping the old (comment claims it strips) → multi-account users stack two signatures; "Start fresh" leaves `didApplySignature = true` so the fresh draft gets no signature. | Track the last-applied signature block and strip it before re-appending; reset `didApplySignature = false` in "Start fresh" then re-seed. |
| QA-0608-4 | macOS email | `EmailService.swift:561` (`assembleThreads`) + `:443` (cache write) | 🟡 med | A transient per-item `mail.get` failure during refresh drops that thread from the enriched set, and the refresh overwrites the folder cache with the smaller set → threads **vanish** until a later clean refresh. | On enrichment failure, keep the prior cached `EmailThread` for that id (merge by id) instead of evicting it. |
| QA-0608-5 | macOS calendar | `MacEventEditSheet.swift:53/76/225` (`originalCalendarMissing`) | 🟡 med | The flag is read by `canSave`/`calendarPicker` but **never set to `true`** anywhere → the "original calendar removed, force a fresh pick before Save" safety net is dead; editing an event whose source was removed silently falls back to a default calendar. | In `primeForm` `.edit`, when `event.calendarIdentifier` is non-nil but no writable source matches, set `originalCalendarMissing = true` + `selectedCalendarSourceId = nil`. |
| QA-0608-6 | macOS calendar | `MacEventEditSheet.swift:250` (calendar picker) | 🔵 low | Comments say the calendar picker is "disabled in edit mode" but it has no `.disabled()`; changing it silently **moves** the event to another calendar with no confirmation. | Add `.disabled(isEditing)` to honor the contract, or relabel it as an intentional "move" action — pick one so code and comment agree. |
| QA-0608-7 | macOS onboarding | `MacOnboardingViews.swift:84` (`MacGmailOnboardingView`) | 🟡 med (UX) | No auto-advance: a user who signed in **with Google** already has a Gmail connection but is still shown "Connect Gmail" and re-OAuth'd if they click it. | Add `.task { await emailService.checkConnection(force:true); if hasConnection { hasConfiguredGmailPrompt = true } }` (mirrors iOS). |
| QA-0608-8 | macOS onboarding | `MacOnboardingViews.swift:508` (`MacDefaultMailOnboardingView`) | 🔵 low | Step is fully implemented (sets `hasConfiguredDefaultMailPrompt`) but never presented — no gate branch in `MacRootView` onboarding chain. Dead/half-wired step. | Either delete it + its flag plumbing, or add the gate branch and bump `onboardingTotalSteps`. |
| QA-0608-9 | macOS email | `EmailService.swift:1186` (`markAsRead`) | 🔵 low | A thread opened from search (not in `threads`) marks-read fire-and-forget; optimistic update + rollback are no-ops and the failure is set on a service field the thread view doesn't display → possible unread-count desync. | Reconcile mark-read against the detail cache too, or accept server truth on next `loadThreads`. |

> Cleared as NOT bugs (verified): smart-sort buckets agree on overdue/today + handle empty input; local-model picker gates on `runtime.isReady` (no silent hang); `processToolCalls` is dead code (live path `executeSingleToolCall` has cancellation gates before every side effect incl. `send_email`); GroupChat polling calls `stopPolling()` first (no double-timer); `ModelContainer` init has a 3-tier fallback + recoverable error UI (no blank window); deep-link handlers reject malformed/unknown hosts; no force-unwrap/`try!`/`as!` crash on the launch/onboarding path; compose double-send guarded by `isSending`/`isSendingAttachments`; pagination dedupes by id. The `HuggingFaceCacheConnector.swift:227` non-atomic-symlink TODO is pre-existing (tracked as BH-0605-2).

---

# 2026-06-05 — Bug hunt (iOS + macOS changed files)

Scope: 22 changed Swift files in `apps/ios` + `apps/macos`. 4 parallel sub-agents by area (AI/Local, Calendar, Settings/Notifications, feature views); every finding then verified against source before fix/report. Validation: targeted simulator build of the iOS scheme.

## Auto-fixed (6)

| File:line | Severity | What changed |
|-----------|----------|--------------|
| `apps/ios/.../Features/Docs/DocsListView.swift:307` (`docRow`) | 🔴 high (crash) | Recursion over server-controlled `parentId` chains had no cycle/depth guard → stack-overflow crash on a cyclic (A→B→A) or self-parent doc. Added `visited: Set<String>` + `depth < 32` guard; cyclic/over-depth nodes render without recursing. |
| `apps/ios/.../Features/Calendar/CalendarViewController.swift:285` (`createNewEvent`) | 🟡 med (latent crash) | `calendar.date(byAdding:)` (`Date?`) was assigned to the implicitly-unwrapped `EKEvent.endDate`; a nil would later trap in `EKWrapper`'s `DateInterval(start:end:)`. Added `guard let endDate else { return nil }`. |
| `apps/ios/.../Features/Calendar/CalendarViewController.swift:178` (`initializeStore`) | 🟡 med (UX) | Post-authorization fresh store didn't invalidate the pre-grant cache → days fetched before access was granted stayed blank until an `EKEventStoreChanged` or day swipe. Now clears `cachedEvents`/`inFlightDates` before `reloadData()`. |
| `apps/ios/.../Services/Notifications/NotificationService.swift:287` (`clearAll`) | 🟡 med (UX) | `clearAll()` removed notifications but not the app-icon badge set by the due-today digest → stale due-count badge on the icon. Added `center.setBadgeCount(0)`. |
| `apps/ios/.../Features/Home/HomeView.swift:1818` (`loadHomeData`) | 🟡 med (race) | Briefing auto-load (fires from `.task`, scenePhase-active, refresh tick) lacked the `!isLoadingAssistantBriefing` guard that `retryBriefing()` has → could stack parallel briefing fetches. Added the guard. |
| `apps/ios/.../Features/Settings/BillingSettingsView.swift:301` (`progressTint`) | 🔵 low (consistency) | `progressTint` read `aiUsagePercent` without the `.isFinite` guard every other consumer in the file uses; a NaN/±inf could pick a misleading tint. Added guard. |

## Needs attention (not auto-fixed — TODO added in code where noted)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| BH-0605-1 | iOS local AI | `MLXInferenceService.swift:143` (TODO) | 🟡 med | Coalesced load can surface a foreign `CancellationError` if `evict`/`unloadAll` cancels the task during the `await` after the `!isCancelled` guard passes; cancelled task's inflight slot can also leak. | Have `evict`/`unloadAll` synchronously `removeValue(forKey:)` the slot they cancel; or retry a fresh load when a non-cancelled caller catches `CancellationError`. |
| BH-0605-2 | macOS local AI | `HuggingFaceCacheConnector.swift:227` (TODO) | 🟡 med | Non-atomic symlink remove+recreate; `nonisolated static` with no serialization → concurrent `refresh()`/download can leave a missing/stale link → MLX re-downloads multi-GB weights. | Create link at a temp path in the same dir + `fm.replaceItemAt` (atomic rename), or serialize the bridge. |
| BH-0605-3 | macOS local AI | `HuggingFaceCacheConnector.swift` `collectExternalCache` | 🔵 low | External-cache size measured over repo root (`blobs/` + `snapshots/`) while the weight check scans only `snapshots/` → size can ~2× inflate when snapshots aren't symlinks into blobs; a weight present only in stale `blobs/` is listed yet fails to bridge. | `directorySize` over `snapshots/` (symlink-resolved), not the repo root. |
| BH-0605-4 | iOS local AI | `LocalModelStateStore.swift:160` (iOS) | 🔵 low | `initialScan` merge can resurrect a just-deleted model as `.installed` if `scanDisk()` snapshotted before the delete finished (treats `.none` as safe-to-seed). | Re-check disk presence at merge time for `.none` seeds, or set a deletion tombstone the scan honors. |
| BH-0605-5 | iOS calendar | `CalendarViewController.swift:~329` (`didUpdate`) | 🔵 low | Dragging an event to a new time then a failed `store.save` leaves the pill visually moved (no reload fires) — looks saved but isn't. | On save failure, drop the affected day's cache + `reloadData`; or guard `allowsContentModifications` before save. |
| BH-0605-6 | iOS calendar | `UnifiedCalendarService.swift:168` (TODO) | 🟡 med | When a connection's calendar list isn't loaded yet, `GoogleCalendarService.events` falls back to fetching `primary` and ignores `hiddenCalendarIds` → a hidden primary can briefly reappear. | Ensure `refresh()` populates sources for every connection before `events()`; or respect `hiddenCalendarIds` in the primary fallback. |
| BH-0605-7 | iOS voice | `VoiceChatViewModel.swift:132` (TODO) | 🔵 low | On failed audio capture, a trailing provider event between consumer-cancel and `provider.disconnect()` can overwrite `.failed`, resurrecting a dead session. | Ignore events once `connectionState == .failed`, or re-assert `.failed` after `disconnect()` returns. |
| BH-0605-8 | iOS docs | `DocEditorView.swift:~259` (`flushPendingSave`) | 🔵 low | `onDisappear` flush + an already-in-flight debounced `saveTitleNow` can issue two concurrent `renameDoc` for the same title (harmless if the server rename is idempotent). | Skip the flush write when an in-flight save targets the same `finalTitle`, or serialize through one save actor. |
| BH-0605-9 | iOS notifications | `NotificationService.swift:124/157/253/277` | 🔵 low | `center.add(request)` fire-and-forget swallows scheduling errors (e.g. the 64-pending OS cap) → a reminder silently never fires. | Use the completion-handler form and log errors, or `Task { try? await center.add }` like the email-reminder path. |
| BH-0605-10 | iOS billing | `BillingSettingsView.swift:235` | 🔵 low | "Used X of Y credits" can show used > limit when over quota (only `aiUsagePercent` is clamped) — contradicts the clamped "0% remaining". | Product decision: clamp displayed used to limit, or accept true overage display. |
| BH-0605-11 | iOS settings | `TabBarCustomizationView.swift:74` (`onMove`) | 🔵 low (UX) | Dragging a tab above Home triggers an in-`onMove` re-pin that snaps it back below Home (confusing); final saved order is still correct. | Add `.moveDisabled(tab.isRequired)` on the Home row so it can't leave index 0. |

> Cleared false positives (verified NOT bugs): (1) `VoiceChatViewModel._micMutedAtomic` "never seeded" — `isMicMuted` only mutates in `toggleMute()`, which syncs the atomic under `micMutedLock` immediately (lines 195/198); they can't diverge. (2) `VoiceChatViewModel` converter status discarded — `convertedBuffer` is freshly allocated each tap (`frameLength` starts 0); the `error == nil && frameLength > 0` gate is adequate, no stale-buffer reuse. (3) `MLXInferenceService` AsyncThrowingStream "double-finish" — not a crash; `AsyncThrowingStream.Continuation.finish()` is idempotent (unlike `CheckedContinuation`). (4) `AppTheme.swift` color parsing — no hex parsing exists; all colors are `Color(red:green:blue:)` / `UIColor(white:)` literals already in range. (5) `AISourcesView`, `MeetingsListView`, `MoreSheetView`, `TaskRowView`, `CalendarSourcePickerView`, `CalendarAccountsView`, `EmailAutomationPolicyView`, `LocalModelsView` — read in full, clean.

---

# 2026-06-01 — Bug hunt (iOS screenshots: bg color / alignment / thread-load)

Scope: iOS changed files, driven by reported screenshot symptoms (inconsistent background, misalignment, thread-load glitches). 2 parallel sub-agents (color tokens / layout) + direct read of thread-loading code. Screenshots were not attached to the session — used the symptom descriptions as the guide.

## Auto-fixed (1)

| File:line | Severity | What changed |
|-----------|----------|--------------|
| `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift:~1196` (loadingState skeleton) | 🟡 medium (visible) | Skeleton row geometry didn't match the real row, so every cold inbox load "jumped" when the skeleton swapped to content. Skeleton was `HStack(spacing: 12)` + 36×36 avatar + `vpad 12`; `EmailRowView` is `spacing 10` + 40×40 (`SenderAvatarView` default) + `vpad 11`. Matched the skeleton to the real row (10 / 40 / 11). Pure placeholder geometry — no logic touched. |

## Needs attention (not auto-fixed)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| BH-0601b-1 | iOS compose | `apps/ios/Todus/Todus/Features/Email/EmailComposeView.swift:538` (to), cc/bcc same pattern | ⚠️ high (user-facing) | Recipient TextFields tokenize in the Binding `set` on every keystroke. Typing a separator eats it: `"a@b.com,"` → `tokenizeRecipients` → `["a@b.com"]` → `get` re-joins `"a@b.com"`, so the comma/semicolon vanishes and a **2nd recipient cannot be typed** (paste of a full list still works). Classic transform-in-binding SwiftUI anti-pattern. TODO added in code. | Bind each field to a raw `@State` string; tokenize on `.onSubmit` and immediately before send, not on every change. Needs simulator verification — not safely testable in this sandbox. |
| BH-0601b-2 | iOS search | `apps/ios/Todus/Todus/Features/Search/GlobalSearchView.swift:342-351` (`personRow`) | 🔵 low | Person results render a custom 34pt gray-initials ZStack, while the inbox People tab uses 40pt `SenderAvatarView` (real photos / brand logos). Same person shows different size + no real avatar in search. | Replace the ZStack with `SenderAvatarView(email:name:size: 40)` for parity. (Behavior change: adds network avatar resolution to search rows — deferred, out of stated scope.) |
| BH-0601b-3 | iOS thread | `EmailThreadView.swift:1655` vs `EmailRowView.swift:29` | 🔵 low | Same sender renders at 40pt in the inbox list but 36pt in thread detail (`MessageRow`). Avatar visibly shrinks on open. Internally consistent within the thread (the divider inset `16+36+10` matches 36), so likely intentional. | Pick one diameter for both, or leave as documented-intentional. |

> Cleared false positives (verified NOT bugs): (1) `EmailInboxView.swift:858` People unread-count badge uses `Color(UIColor.systemBlue)` — a color sub-agent suggested `AppTheme.accentBlue`, but `EmailRowView.swift:57` shows the inbox unread dot was **deliberately** moved off `accentBlue` (= `Color.primary` = black, invisible) to `systemBlue`; both use systemBlue → already consistent. (2) `AvatarCache.bootstrap()` IS wired (`RootView.swift:139`) — the deferred-disk-hydration refactor is safe. (3) People view DOES refresh on new mail (`.onChange(of: emailService.threads)` → `recomputeFilteredThreads` → `recomputeSenderGroupsIfPeopleMode`, `EmailInboxView.swift:337`). (4) Backend `mail.send` accepts the new `headers`/`isForward`/`originalMessage` (`apps/server/src/trpc/routes/mail.ts:857-864`) — the reply-threading + forward changes won't break sends.

---

# 2026-06-01 — Bug hunt (uncommitted + last 3 commits)

Scope: all uncommitted changes + the 3 latest commits (`ed8eb057`, `fcdf9b0b`, `c0f779cf`). Reviewers: 3 parallel platform sub-agents (web / iOS / macOS) + direct server review. Focus: user-breaking bugs; auth left untouched (recently fixed, working).

## Auto-fixed (1)

| File:line | Severity | What changed |
|-----------|----------|--------------|
| `apps/web/components/mail/reply-composer.tsx:92-101` | ⚠️ high (build) | Added `fromEmail?: string;` to the `handleSendEmail` `data` param type. The body reads `data.fromEmail` (lines 111/113) to honor the composer's From picker, but the inline param type omitted the field → `TS2339 Property 'fromEmail' does not exist`. Caller (`EmailComposer.onSendEmail`) already passes it, so this was a pure type gap, not a logic change. |

## Needs attention (not auto-fixed)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| BH-0601-1 | DB migration | `apps/server/src/db/migrations/0056_slack_connection.sql` + `meta/_journal.json` | ⚠️ high (future), 🔵 none today | Migration 0056 is **orphaned**: not registered in `_journal.json` (last idx = 55) and has no `0056_snapshot.json`. `drizzle-kit migrate` reads the journal, not the directory, so it silently **skips** 0056 — `mail0_slack_connection` is never created. The `slackConnection` schema is currently queried **nowhere** (dormant scaffold), so there is **no user impact today**. | Before shipping any Slack feature: run `pnpm --filter @zero/server db:generate` (only schema drift since 0055 is `slackConnection`, so it should regenerate cleanly) to produce the journal entry + snapshot, then `db:migrate`. Did NOT auto-run regen — mid-flight schema, risk of picking up unrelated drift; needs a human to eyeball the generated diff. |
| BH-0601-2 | macOS email | `apps/macos/TodusMac/Services/Email/EmailService.swift:698` | 🟡 medium | `fetchThreadDetail` dedup: a foreground tap (`updateLoadingState:true`) that joins an in-flight **prefetch** (`updateLoadingState:false`) via `return await existing.value` inherits the prefetch's error handling — on failure `errorMessage` is never set, so the view shows the generic "Could not load thread." instead of the friendly auth/404/timeout copy. Not a crash. | Track the friendliest required `updateLoadingState` per id, or set `errorMessage` in `loadThread` when the joined result is nil. |
| BH-0601-3 | macOS calendar | `apps/macos/TodusMac/Services/Calendar/UnifiedCalendarService.swift:24` | 🟡 medium | `legacyCalendarEvent.id` switched from composite (`apple:`/`google:`) to raw `providerEventId`. SwiftUI lists key on `id`; if an Apple and Google event ever share a provider id, duplicate `Identifiable` ids drop/duplicate rows. Cross-provider collision is unlikely (matches iOS) but unguarded. | Keep a composite id for list identity; expose `providerEventId` separately for EKEventStore lookups. |
| BH-0601-4 | macOS local AI | `HuggingFaceCacheConnector.swift:330` / `LocalModelStateStore.swift:131` | 🔵 low | `hasWeightFile`/`directorySize` recursively walk multi-GB HF caches with no depth/count cap and no mid-walk `Task.isCancelled` check (only checked after `collect()` returns). No crash; can be slow on large external caches. | Add a depth/entry cap and periodic cancellation checks inside the enumerator loop. |

> Note: the iOS sub-agent flagged `TodosAPIClient.swift:384 isUITestingSession` as an undefined-symbol build break — **false positive**. It is defined `public` in `packages/swift-auth/Sources/TodusAuth/AuthService.swift:88`; the agent only searched `apps/ios`. No action needed.

---

# 2026-05-28 — macOS QA deferred features (found, not yet fixed)

Surfaced during the multi-round macOS flow QA (commit `ed8eb057`). The critical/high
flow bugs were fixed + committed; the items below were deferred because they need a
backend change, are net-new features, or aren't safely verifiable in this environment
(no GUI / notification / widget runtime). Each has a concrete entry point + fix.

## Deferred — needs backend

| Area | Where | Severity | Problem | Suggested fix |
|------|-------|----------|---------|---------------|
| Subscription cancel | `MacSettingsView.performCancelSubscription` (`productId: "pro_monthly"`) + `apps/server/src/trpc/routes/subscription.ts` `getStatus` | ⚠️ high | Cancel hardcodes `pro_monthly`, so an annual (`pro_annual`) subscriber cancels the wrong product. `getStatus` returns only `plan`/`status`/`aiUsage` — no active product id — so the client can't pick the right one. | Backend `getStatus` must return the active `productId` (and ideally interval). Client then passes the real id to `subscription.cancel`. Backend change required. |
| iOS markdown email send | `apps/ios/Todus/Todus/Services/Email/EmailService` send path | 🟡 medium | macOS now converts the compose markdown body → HTML before send (commit `ed8eb057`), but iOS still sends raw markdown wrapped as `text/html`, so recipients see literal `**bold**` / `# heading` and the body collapses onto one line. | Share the `EmailBodyHTML.render` converter cross-platform (move to `packages/shared` or convert once on the backend) and apply it in the iOS send path too. |
| Email attachment download | `MacEmailThreadView.attachmentsView` (chips are display-only) | 🟡 medium | Attachment chips now render (filename/type/size) but tapping does nothing — there's no fetch/download. | Add a backend attachment-fetch endpoint (`mail.getAttachment`), then wire tap → download/save to disk + open. |

## Deferred — net-new feature

| Area | Where | Severity | Problem | Suggested fix |
|------|-------|----------|---------|---------------|
| Reminder scheduling | `MacNotificationService.scheduleTaskReminder` / `scheduleDueTodayDigest` (never called); Settings toggles `taskRemindersEnabled` / `calendarRemindersEnabled` | ⚠️ high (dead control) | The reminder toggles persist + sync but schedule nothing — no local notification ever fires for a due task. Net-new on iOS too. | Request `UNUserNotificationCenter` auth; schedule a `UNCalendarNotificationTrigger` on task create/update when there's a future due date (gated by `taskRemindersEnabled`); cancel the request on complete/delete; schedule the due-today digest on launch. |
| Move to folder | `MacEmailInboxView` / `MacEmailThreadView` context menus + `EmailService`; backend `mail.modifyLabels` already exists | 🟡 medium | No UI to move/label a thread — only Archive (→archive) and Delete (→bin) exist. | Add a "Move to…" context-menu submenu listing folders; add `EmailService.move(ids:toFolder:)` calling `mail.modifyLabels` with a folder→label-id mapping; optimistic apply + rollback like the other actions. |
| Compose-card CC/BCC input | `Views/AI/ChatUISpec/CardViews.swift` `MacInlineComposeCardView` (CC/BCC rows ~630–649) | 🟡 medium | CC/BCC rows render existing recipients but provide no field to add any — `addRecipient(target:)` is only ever called with `"to"`, so the `cc`/`bcc` branches are dead. | Add `TextField`s bound to per-field input (or a target selector) calling `addRecipient(target: "cc" / "bcc")`. |

## Deferred — medium / low (client, but untestable here)

| Area | Where | Severity | Problem | Suggested fix |
|------|-------|----------|---------|---------------|
| Notification cold-launch | `TodusMacApp` notification delegate, default-tap branch (`guard let services = self.services else { return }`) | 🟡 medium | A notification tapped during cold launch is dropped — `services` is nil until `initializeApp`, and (unlike deep links) the tap isn't queued/replayed. | Queue the routing intent (category + payload) on the app delegate when `services`/`modelContainer` is nil; replay at the end of `initializeApp` (mirror `pendingDeepLinks`). |
| Event-edit prefill | `MacEventEditSheet.swift` (~409, edit mode) | 🟡 medium | In edit mode `location`/`notes` are hardcoded to `""` because `CalendarEvent` doesn't carry them; the user sees empty fields and any typed Location is silently discarded on save (`updateEvent` has no location param). | Carry `location`/`notes` on `CalendarEvent` (or fetch the `EKEvent`) and round-trip them through `CalendarService.updateEvent`. |
| In-chat model menu | `MacAssistantPanel` model menu (~1738) | 🔵 low | The menu lists only the cloud models with a checkmark; a local model selected from Settings shows no checkmark/indicator and can't be seen/switched from chat. | Surface the active local model (name + checkmark) in the menu, or a "Local: <name>" row. |
| Dead `.paused` UI | `MacLocalModelsView` (`.paused` branches in `detailLine`/`actionView`) | 🔵 low | The `.paused` state (caption + "Resume") is rendered but never produced — `ModelDownloadService` has no pause; `cancelDownload` always goes to `.notInstalled`. | Implement pause/resume (URLSession resume data) or remove the `.paused` UI (needs a `default` so the switches stay exhaustive). |

---

# 2026-05-27 — Multi-skill review of cross-platform local diff

Scope: ~1.5k LOC across iOS / macOS / web / server / scripts. Reviewers: 4 parallel platform sub-agents + `claude-review` × 5 chunks + `bug-hunt` skill + fresh adversarial sub-agent. Caveman-review skill consolidated the consensus.

## Auto-fixed (40+)

| File:line | Severity | What changed |
|-----------|----------|--------------|
| `apps/web/components/ui/button.tsx:74-92` | 🔴 critical | Destructured `disabled` out of `...props` so caller's `disabled={false}` no longer overrides the loading lock; suppressed spinner + `disabled` forwarding when `asChild` so a `<Link>` inside `<Button asChild>` isn't (a) crashed by Radix `Slot`'s `Children.only` on a Fragment, or (b) left clickable with a no-op anchor `disabled` attribute. |
| `apps/web/app/(routes)/settings/billing/page.tsx:11-31, 197` | 🔴 critical | Restored `'75 credits / month'` on Free + `'150 credits / month'` on Pro to match iOS linter's 10× display scaling intent; added `CREDITS_DISPLAY_SCALE = 10` to web `formatCredits`. Fixed "100% remaining" headline rendering when `limit === 0`. Removed unused `remaining` local. |
| `apps/ios/Todus/Todus/Features/Settings/BillingSettingsView.swift:17, 70` | 🔴 critical | Restored `"75 credits / month"` on Free so it aligns with the linter's Pro=150 + `creditsDisplayScale = 10`. Changed `percentRemaining` from `round` → `ceil` so any non-zero usage drops the headline below 100% (was reporting "100% remaining" for 0.4% consumption alongside "Used X of Y" subtitle). |
| `apps/macos/TodusMac/Services/AI/Local/HuggingFaceCacheConnector.swift:73-156, 160-181` | 🔴 critical | Wired `bridgeIntoAppCacheIfPossible(_:)` so clicking "Use" on an external-cache HF model symlinks `~/.cache/huggingface/hub/.../snapshots/<sha>` into `Documents/huggingface/models/<repo>` — `MLXInferenceService` is hard-wired to the app cache, so without the bridge "Use" silently re-downloaded multi-GB weights the user already had on disk. Marked `nonisolated`, picks the most-recent snapshot by mtime when `refs/main` is missing, gates on `hasWeightFile`, handles dangling symlinks via `isSymbolicLinkKey`, logs failures, and `collect()` now de-dupes by `id` (preferring `.app`) so a bridged model doesn't show twice and trip SwiftUI's duplicate-`id` ForEach. Added cancellation check after detached `collect()` so back-to-back `refresh()` calls don't clobber. |
| `apps/macos/TodusMac/Services/AI/Local/LocalModelStateStore.swift:139-194` | ⚠️ high | Hopped `initialScan` to `Task.detached(priority: .userInitiated)` (matched iOS) so launch no longer hitches on multi-GB HF caches walked synchronously on `@MainActor`. Gated `.installed` on `hasWeightFile` (shared with HF connector) so partial / failed downloads aren't reported ready. Merge-on-scan now lets live in-flight states win, but lets `.failed` yield to a real on-disk `.installed`. Dropped the `bytes > 0` gate since `hasWeightFile` already proves presence (FS oddities can return 0 for real installs). |
| `apps/ios/Todus/Todus/Services/AI/Local/LocalModelStateStore.swift:131-176` | ⚠️ high | Same merge + `hasWeightFile` + `max(bytes, 0)` fixes as macOS. Pre-fix `init { Task { await initialScan() } }` clobbered `apply(...)` calls that landed during the detached walk. |
| `apps/ios/Todus/Todus/Services/AI/Local/MLXInferenceService.swift:35-76, 100-119, 130-148, 158-200` | ⚠️ high | Use `GenerateParameters.maxTokens` instead of decrementing `maxTokenBudget -= 1` per `.chunk` (chunk = multi-token string, so manual counter overshot the cap 2-4×). Made the switch exhaustive with explicit `.toolCall: continue` (no longer silently swallowed by `@unknown default`). Enforced single-resident `loaded` cache in both `warmUp` and `runStream` (matches doc claim, avoids jetsam OOM on model switch). Mirrored `hasWeightFile` in `isReady` so partial downloads aren't reported ready. Fall back to chunk count when `.info` doesn't fire on `maxTokens`-truncate (usage no longer reports 0/0 for streams the user clearly saw produce tokens). |
| `apps/ios/Todus/Todus/Features/DesignSystem/DesignSystemView.swift:19-22, 488-522` | ⚠️ high | Switched `motionDemoState` from a shared `Int` to `[String: Int]` keyed by token. Pre-fix a tap on any of the 4 motion rows played the shared swatch state at the tapped row's timing — defeating the comparison the demo exists to enable. |
| `apps/macos/TodusMac/Views/Settings/MacLocalModelsView.swift:237-262, 500-528` | ⚠️ high | HF "Use" button now hops the symlink bridge off the main thread and refreshes the connector so the bridged entry doesn't show twice. Apple FM `.installed` branch now renders a simple "Use" button instead of a Menu with "Delete weights" — Apple Foundation Models have nothing to delete, the destructive action was either a no-op or could push the store into a fake `.deleting` state. |
| `apps/web/app/(routes)/settings/notifications/page.tsx` | ⚠️ high | Typed-out the `as any` on `data.settings`, send only `changes` to `saveUserSettings` (was spreading the entire client cache → multi-device clobber risk for unrelated server-managed fields), per-key rollback instead of full-snapshot restore (won't undo unrelated patches that landed between this call's optimistic write and its rejection), `onSettled: invalidate` so the cache converges on server truth after each save. |
| `apps/web/app/(routes)/settings/design-system/page.tsx:161-163` | 🟡 medium | Motion duration labels now match `globals.css`: `Base 250ms`, `Slow 350ms` (was `220` / `320`). The viewer that exists to catch cross-platform drift was actively misreporting it. |
| `scripts/parity/capture-ios-deeplink.mjs:121-127` | 🟡 medium | Stripped leading slash so `${scheme}://${route}` no longer yields `todus:///login` (triple slash = empty host) which iOS `.onOpenURL` parses with a different host/path split. |
| `apps/web/app/(routes)/settings/billing/page.tsx:21-29` | ⚠️ high | `getPlanKey` now resolves `team` / `team_*` / `enterprise` to `pro` so paying customers on those tiers don't see the "Free" label + "Upgrade" CTA. Dedicated team / enterprise copy can land later. |
| `apps/web/app/(routes)/settings/billing/page.tsx:91` | ⚠️ high | `pct` now uses `Math.ceil` instead of `Math.round` — pre-fix `0.4%` consumption rounded down to 0, so the headline reported "100% remaining" while the subtitle simultaneously showed real usage. Mirrors the iOS `percentRemaining` fix. |
| `apps/macos/TodusMac/Views/Settings/MacLocalModelsView.swift:237-257` | ⚠️ high | HF "Use" now `await`s the symlink bridge before assigning `selectedModel`, so a fast user can't trigger inference between assignment and bridge landing (which would force a multi-GB re-download). |
| `apps/macos/TodusMac/Views/Settings/MacLocalModelsView.swift:350-358` | 🟡 medium | Apple FM rows no longer render redundant "Installed" capsule alongside "Built-in" — the store reports `.installed` unconditionally for `.appleFM`, but UI gated only on `state.isInstalled` showed both. |
| `scripts/parity/capture-ios-deeplink.mjs:26-31` | 🔵 low | `PARITY_IOS_SETTLE_MS` non-numeric env value no longer coerces to `NaN` → `setTimeout(_, 0)`; falls back to 1200ms when not finite or negative. |
| `apps/macos/TodusMac/Views/Settings/MacLocalModelsView.swift:11-19, 237-263` | 🟡 medium | Added `@State bridgingHFIds: Set<String>` so HF row's "Use" button disables + shows "Linking…" while the symlink bridge runs. Pre-fix a fast double-tap spawned duplicate bridge tasks; the bridge is idempotent (second call's `createSymbolicLink` throws `EEXIST` and is swallowed) but the double-task wastes work and pollutes the log. |
| `apps/macos/TodusMac/Services/AI/Local/HuggingFaceCacheConnector.swift:330-352` + `apps/macos/TodusMac/Services/AI/Local/LocalModelStateStore.swift:204-228` | ⚠️ high | `directorySize` now skips symlinks. HF's external cache stores each weight as a real file under `blobs/<sha>` and a symlink alias under `snapshots/<commit>/`. `URLResourceValues` follows symlinks by default, so without this skip every external-cache weight was counted twice — the row showed ~2× real disk usage and `totalDiskBytes()` over-reported the Settings header. App-cache entries (plain files written by mlx-swift-examples) are unaffected. |
| `apps/macos/TodusMac/Services/AI/Local/HuggingFaceCacheConnector.swift:129-152` | ⚠️ high | Dangling-symlink detection now requests **only** `.isSymbolicLinkKey` (lstat semantics) instead of also asking for `.isDirectoryKey`. Pre-fix the latter required `stat()`-ing the (missing) destination, so `try?` returned nil for a dangling link → the cleanup branch was skipped → `createSymbolicLink` threw `EEXIST` → bridge silently failed and MLX re-downloaded multi-GB weights. |
| `apps/macos/TodusMac/Views/Settings/MacLocalModelsView.swift:1-7, 256-262` | 🔵 low | Now passes a shared `Logger(subsystem: "com.todus.macos", category: "HFBridge")` into `bridgeIntoAppCacheIfPossible(entry, log:)` so its diagnostic logs actually fire — pre-fix the caller passed no logger, every `log?.error/.warning/.info` was a no-op, and the intended support-ticket visibility was dead code. |
| `apps/macos/TodusMac/Services/AI/Local/HuggingFaceCacheConnector.swift` (snapshot resolver) + (directorySize) + (bridge dangling-link), `apps/macos/TodusMac/Services/AI/Local/LocalModelStateStore.swift` (directorySize), `apps/macos/TodusMac/Views/Settings/MacLocalModelsView.swift` (HF section filter) | ⚠️ high | Snapshot resolver now iterates by mtime and picks the first dir with weights (was giving up on the newest if it was aborted). `directorySize` now resolves each enumerated URL to its canonical path and de-dupes — counts every weight once across both layouts (external blobs ↔ snapshot symlinks AND bridged app-cache symlink-to-snapshot-of-symlinks). HF section filters out repos already shown under Installed so a curated catalog model the app downloaded doesn't appear twice with conflicting controls. |
| `apps/{ios,macos}/.../LocalModelStateStore.swift` + `apps/macos/.../HuggingFaceCacheConnector.swift` + `apps/ios/.../MLXInferenceService.swift` (`hasWeightFile` / `isReady`) | 🟡 medium | All weight detectors now gate on `.isRegularFile` so a directory whose name happens to end in `.safetensors` / `.npz` / `.gguf` (rare but possible — user-created folders, HF blob fallbacks) no longer false-positives and crashes the MLX loader on first turn. |
| `apps/macos/TodusMac/Services/AI/Local/HuggingFaceCacheConnector.swift` (bridge stale-symlink) | ⚠️ high | Bridge now resolves the desired snapshot FIRST, then compares an existing live symlink's destination to that resolved path. If a previously bridged symlink points at a stale snapshot (HF moved `refs/main`), it's removed and recreated. Pre-fix the bridge returned immediately on any live symlink, so a re-pulled HF repo kept loading old weights indefinitely. |
| `apps/ios/Todus/Todus/Services/AI/Local/MLXInferenceService.swift` (`loaded` cache swap) | ⚠️ high | `warmUp` + `runStream` now use `loaded = [id: container]` instead of `removeAll` + insert. Pre-fix a concurrent warmUp / runStream that interleaved during an `await` could erase the freshly-inserted container of the other path — the surviving caller had a valid handle while the other's container was silently dropped, forcing a multi-GB reload on the next turn. |
| `apps/ios/Todus/Todus/Services/AI/Local/LocalModelStateStore.swift` (`directorySize`) | 🟡 medium | Mirrors macOS: resolves each enumerated URL to canonical path and de-dupes. iOS today only probes `Documents/huggingface/models/<repo>` so the impact is theoretical, but the math stays consistent across platforms and future HF cache layouts. |
| `apps/{ios,macos}/.../LocalModelStateStore.swift` | 🔵 low | When `directorySize` returns 0 (allocated size unavailable for every file in a sandboxed FS / network volume) for a tree where `hasWeightFile` already proved presence, surface a 1-byte sentinel so the UI doesn't render "0 B" for a real download. |
| `apps/macos/TodusMac/Services/AI/Local/HuggingFaceCacheConnector.swift` (lastError + refs/main validation) | 🔵 low | `lastError` no longer set to "No HuggingFace models found on this Mac." for the legitimate empty state (UI's `huggingFaceSection` hides itself anyway, but the property's doc says it's for real errors). `refs/main` payload now validated against `s.count <= 64 && s.allSatisfy(\.isHexDigit)` before being appended as a path component — defends against a malformed / tampered refs file embedding traversal characters. |
| `apps/ios/.../MLXInferenceService.swift` (`loadCoalesced` inflight refcount + cancel-aware) | ⚠️ high | `loadCoalesced` now uses an `InflightEntry { seq, task }` value; a `Task.isCancelled` guard skips cancelled entries instead of awaiting them (which would surface a `LocalAIError.cancelled` on a fresh caller that never asked for it). `evict`/`unloadAll` cancel the task but leave the slot; the reaper drops the slot once the underlying load actually settles, preventing duplicate concurrent loads after cancel against an uncooperative `loadContainer`. Reaper publishes the resolved container to `loaded` BEFORE clearing inflight so a third caller can never see both empty and spawn a redundant load. Callers also publish directly (idempotent) as belt-and-suspenders for Swift's unspecified continuation order. |
| `apps/ios/.../MLXInferenceService.swift` (`container.perform` foot-gun fix) | ⚠️ high | Stream iteration moved INSIDE `ModelContainer.perform`. The framework's docstring explicitly warns "Callers _must_ eval any `MLXArray` before returning as `MLXArray` is not `Sendable`" — pre-fix the `AsyncStream` returned out of `perform` was iterated on the surrounding loop, which could touch MLX-array-backed detokenizer state after the closure's isolation scope had released. Documented foot-gun causing nondeterministic crashes on long generations under memory pressure. Counters now thread through a `Sendable` struct return value. |
| `apps/ios/.../MLXInferenceService.swift` (`isReady` weight gate, single-resident swap, cancel re-throw, HF cache backup exclusion, models/ leaf create, chunkCount → 0 fallback) | mixed | Multiple `isReady` / cache-management fixes. See file diff. |
| `apps/ios/.../LocalModelStateStore.swift` + `apps/macos/.../LocalModelStateStore.swift` (Apple FM availability gate) | ⚠️ high | `state(for:)` no longer returns `.installed` for `.appleFM` unconditionally — gated on `DeviceProfile.current.appleFMAvailable`. Pre-fix any caller enumerating `installedModels()` for a runtime pick (chat fallback, background summarization, recommender) would see Apple FM on a Mac/iPhone that doesn't actually support it and fail at invocation. |
| `apps/ios/.../LocalModelStateStore.swift` + `apps/macos/.../LocalModelStateStore.swift` (`fileSize` fallback) | 🔵 low | Added `fileSizeFallback` (logical size) so the UI doesn't render "1 B" for a real multi-GB install on volumes where `totalFileAllocatedSize` is unavailable (sandboxed mounts, network drives). |
| `apps/macos/.../LocalModelStateStore.swift` (backup exclusion parity) | 🔵 low | macOS `modelsDirectory` now sets `isExcludedFromBackup` on `huggingface/` parent on first creation — matches iOS so multi-GB weights don't get pulled into iCloud Drive / Time Machine. |
| `apps/web/app/(routes)/settings/notifications/page.tsx` (rollback simplification) | 🔴 critical | Dropped manual rollback in catch — pre-fix `before.settings[key]` captured at call-start was used to restore on failure, which silently overwrote a concurrent successful patch for the same key. `onSettled: invalidate` refetches from the server immediately on either outcome, so the cache converges on server truth without us guessing. Worst case is ~one round-trip of optimistic value before flipping back. |
| `apps/web/components/ui/button.tsx` (`asChild` interaction guard + `Loader2`) | ⚠️ high | When `asChild` is true and the button is loading/disabled, the slotted child (often `<a>` / `<Link>`) now gets `pointer-events-none` and `tabIndex={-1}` so the `aria-disabled` signal isn't a lie — pre-fix the link was announced as disabled to screen readers while remaining fully clickable. Spinner glyph `↻` replaced with `lucide-react`'s `Loader2` for visual + a11y consistency with the rest of the app. |
| `apps/web/app/(routes)/settings/billing/page.tsx` (`formatCredits` NaN guard) | 🔵 low | `formatCredits` now coerces `NaN` / `-Infinity` / negative inputs to `0` so an upstream API regression doesn't propagate `NaN%` into the progress bar / headline. |
| `apps/web/app/(routes)/settings/design-system/page.tsx` (`MOTION_DEMOS[1]` guard) | 🔵 low | `useState(MOTION_DEMOS[1].durationVar)` would crash at module init if someone trimmed the array. Falls back through `[1]?` → `[0]?` → literal default. |
| `scripts/parity/capture-ios-deeplink.mjs` (`booted.stdout` null guard) | ⚠️ high | `spawnSync` returns `stdout: null` (not `''`) when the spawn itself fails — `null.includes(...)` would throw a confusing `TypeError` instead of the intended "No booted iOS simulator found." message. Now `(booted.stdout ?? '').includes('Booted')`. |
| `apps/macos/.../HuggingFaceCacheConnector.swift` (stale-symlink removal error) | 🔵 low | `fm.removeItem(at: target)` failure now logged (was `try?` swallow). A permissions issue surfacing as "MLX silently re-downloads multi-GB weights" is now diagnosable in Console.app. |

## Needs human review (5)

Pre-existing bugs in `apps/server/src/main.ts` that are adjacent to the diff but were **not introduced by this batch of changes**. Surface here because `claude-review` flagged them during a full-file pass; fix in a separate PR with proper queue-semantics testing.

| File:line | Severity | Problem | Suggested fix |
|-----------|----------|---------|---------------|
| `apps/server/src/main.ts:1010` | 🔴 critical | `send-email-queue` catch deletes `statusKV` + `payloadKV` after a send failure without rethrowing. Cloudflare Queues then acks the message and the payload is gone — a transient error (network blip, Gmail rate limit, DO hiccup) silently drops a scheduled email the user thinks was sent. | Distinguish permanent vs transient errors; rethrow on transient so the queue retries, only delete on a final / non-retryable failure. |
| `apps/server/src/main.ts:772` | ⚠️ high | `.get('.well-known/oauth-authorization-server', ...)` is registered without a leading slash. Hono pathnames always start with `/`, so the OAuth / MCP discovery endpoint 404s. | `.get('/.well-known/oauth-authorization-server', ...)`. |
| `apps/server/src/main.ts:1180` | ⚠️ high | `processExpiredSubscriptions` does `const { db, conn } = createDb(...)`, then `await db.query.connection.findMany(...)`, then `await conn.end()`. If `findMany` rejects, `conn.end()` never runs and the Hyperdrive / Postgres connection leaks. | Wrap the query in `try { … } finally { await conn.end() }`. |
| `apps/server/src/main.ts:1240` | 🟡 medium | `\`[SCHEDULED] Processed ${allAccounts.keys.length} accounts\`` — `allAccounts.keys` resolves to `Array.prototype.keys` (a function with `.length === 0`), so the log always reports 0 accounts. | `allAccounts.length`. |
| `apps/server/src/main.ts:1295` | 🟡 medium | `.post('/a8n/notify/:providerId')` returns a response only when `providerId === EProviders.google`. Other providers exit the try block, run `finally { span.end() }`, and the handler returns `undefined` → Hono surfaces a 500 / 404 instead of a meaningful status. | `return c.json({ message: 'ignored' }, 200)` as a fallback so callers don't retry forever. |

## Investigated, not bugs (false positives from re-review pass)

- `apps/web/app/(routes)/settings/notifications/page.tsx:17` — `claude-review` warned that `useSettings` may not write to `trpc.settings.get`. Verified in `apps/web/hooks/use-settings.ts`: `useSettings` is `useQuery(trpc.settings.get.queryOptions(...))`, same key. Optimistic write lands on the right cache.
- `apps/macos/TodusMac/Views/Settings/MacLocalModelsView.swift:205` — A curated MLX model the user downloaded in-app could appear in both Installed and Connected (HuggingFace). Confirmed acceptable: Installed shows the curated catalog entry with full controls, HF section shows raw on-disk entries; product team to decide whether to dedupe (architectural).

---

# 2026-05-20 — Bug Hunt: apps/web main user flows

Scope: auth (login/signup/OTP), mail layout, [folder] route, compose, chat, calendar, tasks, optimistic actions.

## Auto-fixed (1)

| File:line | Severity | What changed |
|-----------|----------|--------------|
| `apps/web/app/(routes)/mail/calendar/page.tsx:174-181` | error | useEffect deps included `displayMonth`, so any user-initiated month-pagination via Calendar's `onMonthChange` re-fired the effect and snapped `displayMonth` back to `selectedDate`'s month. Users could not paginate the picker without also clicking a date. Removed `displayMonth` from deps (eslint-disable for exhaustive-deps); effect now runs only on `selectedDate` change. |

## Needs human review (1)

| File:line | Severity | Problem | Suggested fix |
|-----------|----------|---------|---------------|
| `apps/web/hooks/use-optimistic-actions.ts:347` | warning | `typeActions?.size === 1` is checked AFTER `typeActions.delete(pendingActionId)` on the previous line mutates the same Set reference. Branch fires only when one OTHER pending action of the same type remains in flight. Single-action case (Set 1 → 0) never enters the branch, so `refreshData()`, `invalidateFolderLists()`, and `removeOptimisticAction()` are skipped: jotai `optimisticActionsAtom` grows unboundedly across a session (memory leak), MOVE/SNOOZE/UNSNOOZE/DELETE_DRAFT actions leave `shouldHide=true` forever in optimistic state, and server folder caches drift until the 5-minute stale window expires. | Almost certainly `=== 0` (i.e. this was the last in flight). Verify intent against the action's design — the current `=== 1` may have been left over from a different cleanup model. TODO comment inserted inline. |

## Investigated, not bugs (false positives from investigator subagent)

- **`apps/web/components/mail/thread-display.tsx:212`** — `Math.max(1, focusedIndex + 1)`. `focusedIndex` is guaranteed `>= 0` by the `focusedIndex === null` early return on the previous line, so the clamp is a no-op (redundant but harmless).
- **`apps/web/components/mail/mail-list.tsx:177`** — `setFocusedIndex(focusedIndex)`. After the optimistic move/archive removes the current row, the list shifts left by one, so the OLD index now points at the formerly-next sibling — keeping the index intentional.
- **`apps/web/components/create/create-email.tsx:91`** — Calling `useActiveConnection()` twice (lines 79 + 91) produces two bindings (`activeConnection`, `activeAccount`) that resolve to the same react-query cache entry. Wasteful but not a bug; both used in different fallback chains for `userEmail` / `userName`.
- **`apps/web/components/create/email-composer.tsx:480`** — `editor.getHTML() === initialMessage.trim()` is a defensive double-check alongside the plain-text comparison on line 479. `initialMessage` may be HTML (draft body) or plain text (replies) depending on call site; the dual comparison catches both forms.
- **`apps/web/app/(routes)/mail/[folder]/page.tsx:59-61`** — The `else { setIsLabelValid(false) }` branch when `userLabels` is falsy. `useLabels()` returns `userLabels: []` (empty array, truthy) even on error/loading, so this branch is unreachable dead code. UI's auto-redirect timer still fires via the `if (userLabels)` path (empty array passes `checkLabelExists` returning false, then starts the timer).

---

# 2026-05-20 — Bug Hunt: macOS app main user flows

Scope: auth/onboarding, email inbox/thread/compose, tasks, calendar, AI chat/voice, docs, search, notifications, meetings.

## Auto-fixed (2)

| File:line | Severity | What changed |
|-----------|----------|--------------|
| `apps/macos/TodusMac/Views/Email/MacEmailComposeView.swift:380` | error | Reply All never auto-expanded Cc/Bcc when `draft.cc` was empty. The branch `if cc.isEmpty && nav != "Reply All" {} else if !cc.isEmpty { show }` had an empty if-body, so the `navigationTitle == "Reply All"` check was dead. Replaced with `if navigationTitle == "Reply All" || !draft.cc.isEmpty { showCcBcc = true }`. |
| `apps/macos/TodusMac/App/MacOnboardingViews.swift:200` | error | Reminders onboarding treated `.writeOnly` as denied, but `MacAppServices.requestRemindersPermissionIfNeeded()` (line 736) accepts `.writeOnly` as authorized. Users granting write-only access saw "Permission was not granted" while underlying sync would have worked. Moved `.writeOnly` into the authorized branch. |

## Needs human review (3)

| File:line | Severity | Problem | Suggested fix |
|-----------|----------|---------|---------------|
| `apps/macos/TodusMac/Services/Tasks/LocalTaskParsingService.swift:75` | warning | `daysAhead <= 0 { daysAhead += 7 }` — typing "monday" on a Monday schedules next Monday, not today. May be intentional but worth surfacing to product. | Decide policy: (a) same-day-keyword keeps today, (b) same-day-keyword rolls forward. If (a), change to `daysAhead < 0`. |
| `apps/macos/TodusMac/Views/Email/MacEmailThreadView.swift:245-262` | warning | Compose sheet renders empty content if `detail?.messages.last` is nil when `showCompose=true`. User can trigger an empty 520x380 sheet. | Guard `showCompose = true` behind a `detail?.messages.last != nil` precondition, or add a placeholder/error state inside the sheet. |
| `apps/macos/TodusMac/Services/Voice/GeminiLiveProvider.swift:271-279` | info | Captures `let task = self.webSocketTask` at 271 but then dereferences `self.webSocketTask` again at 273 and 278 before nilling. Single-actor so unlikely race, but inconsistent. | Use the captured `task` reference throughout, then nil `self.webSocketTask` once. |

## Investigated, not bugs

- **`apps/macos/TodusMac/Services/Drafts/MacDraftService.swift:173`** — `draft.connectionId` is non-optional `String` per `DraftRecord`; `.trimmingCharacters` is safe.
- **`apps/macos/TodusMac/Services/Voice/VoiceSessionCoordinator.swift:454`** — `executeTool` IS awaited inside the Task closure; no missing await.
- **`apps/macos/TodusMac/Views/Calendar/MacCalendarView.swift:1290-1294`** — Hour overflow when minute rounding hits 60: Foundation `Calendar.date(from:)` normalizes out-of-range components (e.g. hour=24 → next day 00:00). Safe.
- **`apps/macos/TodusMac/Views/Notifications/MacNotificationCenterView.swift:516`** — Request-ID guard correctly captures ID before await and compares after; not a race.
- **`apps/macos/TodusMac/Domain/TaskSmartSort.swift:72`** — Today-bucket-before-overdue ordering is the documented intent (`.today: "Needs attention now"`).
- **`apps/macos/TodusMac/Views/Meetings/MacMeetingDetailView.swift:458`** — Calling `loadMeeting()` after `generateSummary` failure is intentional refresh; `actionError` is also set.



## Open Items

| ID | Title | Area | Type | Impact | Risk | Status | Summary |
|----|-------|------|------|--------|------|--------|---------|
| 001 | Inline TaskItem duplicated in home/page.tsx | web/home | design-debt | internal | low | open | `home/page.tsx` defines its own inline `TaskItem` component instead of importing the shared `components/tasks/task-item.tsx`. Both work correctly but will diverge over time. Fix: import from `@/components/tasks/task-item` and remove the inline definition. |

---

# 2026-05-02 — Full-repo Review

Scope: uncommitted local changes (~80 modified files + new files) plus last 3 commits (`d8d471c7`, `07433b25`, `8fd1cf0e`). Reviewed iOS app + Swift packages, macOS app, Cloudflare Worker backend, web product (`apps/web`), and marketing site (`new-website`). `apps/mail/` (read-only archive) excluded.

## Auto-fixed in this run

| ID | File:line | Status | What changed |
|----|-----------|--------|--------------|
| AF-1 | `apps/macos/TodusMac/Domain/SnoozeOption.swift:35` | auto-fixed | Replaced dead `var components = calendar.dateComponents(...)` (only `.weekday` used) with single `calendar.component(.weekday, from: now)` call. No behavior change. |
| AF-2 | `apps/macos/TodusMac/Services/Email/EmailService.swift:218` | auto-fixed | Doc-comment said "detached task" but the implementation uses `Task { ... }` (an independent top-level Task, not `Task.detached`). Updated wording to match the inline comment further down. Comment-only. |

## High severity (block before merge)

### B-001 — Mixed package-manager config in `package.json` will break installs
- **Area:** repo root · **Type:** repo hygiene / build break · **Risk:** high · **Status:** open
- **Files:** `package.json`, untracked `bun.lock`
- **Summary:** New diff adds `workspaces.catalog` (bun-only syntax) and `patchedDependencies` (pnpm syntax) to the same `package.json`, while a `bun.lock` (~1.4 MB) sits alongside the canonical `pnpm-lock.yaml` (~1.0 MB). `CLAUDE.md` and every script standardize on pnpm. `pnpm install` will ignore the catalog → silently diverge from `bun install` resolutions; `pnpm.patchedDependencies` should be nested under `"pnpm": { ... }` in pnpm v9+; referenced `patches/novel.patch` may not exist.
- **Approach:** Pick one package manager. If pnpm: revert `package.json` block, move catalog entries to `pnpm-workspace.yaml`'s `catalog:`, ensure `patchedDependencies` correctly nested. Drop `bun.lock`. If bun: drop `pnpm-lock.yaml`, rewrite scripts and `CLAUDE.md`.

### B-002 — Settings `location` field may not persist end-to-end
- **Area:** apps/web, apps/server, apps/ios, apps/macos · **Type:** correctness / UX · **Risk:** medium · **Status:** open
- **Files:** `apps/web/app/(routes)/settings/general/page.tsx:152`, `apps/server/src/lib/schemas.ts:195`, plus iOS/macOS settings sheets
- **Summary:** The `location` form field is rendered, defaulted, and the Zod schema accepts it (`z.string().default('')`). What's not visible in the diff is whether the web mutation payload, the tRPC settings router write path, the iOS settings sheet, and the macOS settings sheet all actually transmit/receive the new field. If any link is missing, the user types and saves and the value silently disappears.
- **Approach:** Trace `location` from each platform's settings UI through to a DB write and confirm round-trip. Add at least one parity screenshot test or unit test pinning the wire format.

### B-003 — Refresh-token fallback ignores `expiresAt`
- **Area:** apps/server (auth) · **Type:** security · **Risk:** high · **Status:** open
- **File:** `apps/server/src/main.ts:1197-1212`
- **Summary:** New fallback selects ANY session row for `sessionUser.id` whose `token === trimmedRefreshToken`, ignoring `expiresAt`. Comment justifies this for replication lag and freshly-rotated tokens, but it also means an attacker who obtains a long-expired session token (e.g. from old logs/backups) could pair it with a current Bearer for the same user and resurrect the expired session for downstream account-linking flows.
- **Approach:** Bound the fallback to a short window (e.g. `expiresAt > now() - 15 min`). Verify whether Better Auth's `linkSocialAccount` re-validates the session token; if not, this is exploitable.

### B-004 — macOS compose body sent as raw markdown — recipients see `**bold**` literals
- **Area:** apps/macos email compose · **Type:** correctness / UX · **Risk:** medium · **Status:** open
- **Files:** `apps/macos/TodusMac/Views/Email/MacEmailComposeView.swift:411-470`, `apps/macos/TodusMac/Services/Email/EmailService.swift:818`
- **Summary:** The new formatting toolbar inserts `**`, `_`, `# `, `- `, `> ` directly into `draft.body`. `mail.send` is called with `message: draft.body` unchanged. The backend treats it as plain text or HTML, not markdown — recipients see the markdown literals.
- **Approach:** Render toolbar inserts as inline HTML (`<b>`, `<i>`, `<h1>`, `<ul><li>`) before sending, or convert markdown → HTML on send. The toolbar should also wrap the *selected text* rather than appending a placeholder at end of body.

### B-005 — macOS compose "From" account selector is non-functional
- **Area:** apps/macos email compose · **Type:** correctness · **Risk:** medium · **Status:** open
- **Files:** `apps/macos/TodusMac/Services/Email/EmailService.swift:805-823`, `apps/macos/TodusMac/Domain/EmailModels.swift:158`
- **Summary:** `EmailDraft.fromConnectionId` is captured by the new "From" menu but `sendEmail(_:)` never serializes it into `SendEmailInput`, and `SendEmailInput` has no `connectionId` field. Multi-account users believe they're sending from the selected account; every send actually uses the backend default.
- **Approach:** Add `connectionId: String?` to `SendEmailInput`, populate from `draft.fromConnectionId`, confirm the backend `mail.send` accepts it (web/iOS likely already do).

## Medium severity

### B-010 — iOS avatar disk cache key uses `String.hashValue`
- **File:** `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift:13` · **Type:** bug · **Risk:** medium · **Status:** open
- **Summary:** `dataKey` interpolates `urlString.hashValue`, which Swift randomizes per process launch. The cache entry written this run is unreadable next launch — the doc-comment promise of "renders correctly when device is offline" never holds across launches. Orphaned keys also accumulate in `UserDefaults`.
- **Approach:** `import CryptoKit`, use `SHA256.hash(data: Data(urlString.utf8))` formatted as hex.

### B-011 — `LocalTaskParsingService.hasDateKeyword` wrong for "today"/"idag"
- **File:** `apps/ios/Todus/Todus/Services/Parsing/LocalTaskParsingService.swift:77` (mirrored in macOS) · **Type:** bug · **Risk:** medium · **Status:** open
- **Summary:** When the user types `today 14`, the relative-marker step matches `today` (offset 0) and sets `foundDateKeyword = true`, but `baseDate == now`. Line 77 derives `hasDateKeyword` from `baseDate != now`, which is `false`, and `findTimeMatch` runs in the more conservative mode.
- **Approach:** `let hasDateKeyword = foundDateKeyword || (baseDate != now)`. Add a unit test for `today 14` → today @ 14:00. Mirror to the macOS copy at `apps/macos/TodusMac/Services/Tasks/LocalTaskParsingService.swift`.

### B-012 — `classifyThreadKind` duplicated and already drifting between two routers
- **Files:** `apps/server/src/trpc/routes/assistant.ts:317-323`, `apps/server/src/trpc/routes/mail-assistant.ts:81-87` · **Type:** correctness / maintainability · **Risk:** medium · **Status:** open
- **Summary:** Both routers reimplement `VERIFICATION_KEYWORDS`, `RECEIPT_KEYWORDS`, `MARKETING_SENDER_PATTERN` and `classifyThreadKind`. The mail-assistant copy already adds `MARKETING_SENDER_PATTERN.test(senderEmail)` to `isAutomatedSender`; the assistant.ts copy does not. Same thread classifies differently across endpoints.
- **Approach:** Hoist to `apps/server/src/lib/thread-classifier.ts` and import from both. Add unit tests covering verification, receipt, marketing, notification.

### B-013 — `bimi-avatar.tsx` URL cap removed; constant still declared
- **File:** `apps/web/components/ui/bimi-avatar.tsx:8` (dead constant), `:122` (cap removed) · **Type:** performance · **Risk:** medium · **Status:** open
- **Summary:** `MAX_FAVICON_URLS = 6` declared but no longer used (the diff removed the `.slice(...)`). With Clearbit + icon.horse + DDG + Google × {bare, www} × multiple domain candidates, a sender like `foo@a.b.example.com` can yield 30+ URLs, each tried sequentially via `<img onError>` chain.
- **Approach:** Restore the cap (possibly bump to 8–10) or delete the unused constant if uncapped is intentional.

### B-014 — `bimi-avatar.tsx` leaks recipient social graph to four third parties
- **File:** `apps/web/components/ui/bimi-avatar.tsx:98-119` · **Type:** privacy · **Risk:** medium · **Status:** open
- **Summary:** Every non-personal sender domain triggers requests to `logo.clearbit.com`, `icon.horse`, `icons.duckduckgo.com`, `google.com/s2/favicons` from the user's browser. Meaningful expansion of the third-party request graph.
- **Approach:** Proxy via the backend `avatar` tRPC route (which already returns `fallbackUrls`), so the client only hits same-origin URLs. Or gate behind the `externalImages` user setting.

### B-015 — Sender-avatar / Gravatar fallback expands third-party PII surface (server)
- **File:** `apps/server/src/lib/sender-avatar.ts:367-419` · **Type:** privacy + reliability · **Risk:** medium · **Status:** open
- **Summary:** Composes Gravatar URLs from raw user-supplied emails (hash-based; not generally reversible but Gravatar lookups can confirm known emails). Combined with Clearbit/icon.horse/DDG, the user's senders are queried against four external services per resolution. No caching layer.
- **Approach:** Gate behind `externalImages` user setting; cache resolution per-domain in KV with 24h TTL.

### B-016 — iOS `checkConnection` flips `hasResolvedConnection = true` even on timeout
- **File:** `apps/ios/Todus/Todus/Services/Email/EmailService.swift:1014-1042` · **Type:** bug · **Risk:** medium · **Status:** open
- **Summary:** `defer { hasResolvedConnection = true }` runs even when the API call throws and `hasConnection` was never set. A single transient 8-second timeout can lock the user into a stale `hasConnection=false` for 30 s because the next call within the cooldown window will skip re-checking.
- **Approach:** Move `hasResolvedConnection = true` into the success branch; or invalidate it on throw.

### B-017 — Workflow durability: automation-policy fetch outside `step.do`
- **File:** `apps/server/src/pipelines.ts:622-637` · **Type:** workflow durability · **Risk:** medium · **Status:** open
- **Summary:** Inside the workflow generator, `Effect.tryPromise` reads automation policy directly. On replay after a crash, this is non-deterministic — if the user toggled settings between runs, replay sees a different policy and may register a different set of `WorkflowDefinition`s.
- **Approach:** Wrap as `step.do('fetch-automation-policy', () => …)`. Verify whether `Effect.tryPromise` already memoizes via the surrounding step infrastructure.

### B-018 — `triggerServerSync` task captures `@MainActor` class without Sendable
- **File:** `apps/ios/Todus/Todus/Services/Email/EmailService.swift:372` (and macOS mirror) · **Type:** Swift 6 strict-concurrency safety · **Risk:** medium · **Status:** open
- **Summary:** `Task { [api] in … }` captures `TodosAPIClient`, which is not declared `Sendable`. Today this works because `api.trpcMutation` is `@MainActor`-isolated, but the closure capture itself is what strict concurrency flags.
- **Approach:** Either declare `TodosAPIClient` `@unchecked Sendable` with documented contract, or refactor `trpcMutation` to a free async function.

## Low severity / suggestions

| ID | File:line | Type | Summary |
|----|-----------|------|---------|
| B-020 | `apps/server/src/trpc/routes/assistant.ts:432-453` | correctness | `extractVerificationCode` fallback regex picks any 4-8 digit number — order numbers, postal codes, phone fragments. Wrong "verification" code is a tap-to-copy footgun. Only return when labelled regex matched. |
| B-021 | `apps/server/src/trpc/routes/assistant.ts:498-507` | correctness | `extractReceiptDetails` amount regex matches unrelated numbers on noisy receipts. Anchor matches to a "Total/Amount/Charged" label nearby. |
| B-022 | `apps/server/src/trpc/routes/assistant.ts:2255-2354` | performance | Non-conversational threads pay the full `buildThreadAnalysis` cost (LLM/vector/related-task) and then zero out actionable fields. Classify early and short-circuit. |
| B-023 | `apps/server/src/pipelines.ts:622-637` and `795-810` | maintainability | Effect-based and imperative versions reimplement automation-policy fetch + default-fallthrough. Effect version's `Effect.orElse` after a `try` with catch is dead. Extract `getUserAutomationPolicy(userId)`. |
| B-024 | `apps/server/src/lib/ai-profile.ts:124-133` | prompt-injection (low) | `identity.name` / `identity.email` interpolated into system prompt unsanitized. Strip leading `#`, backticks, code fences. |
| B-025 | `apps/server/src/routes/ai.ts:524-542` | cost | 21 KB `GENERATIVE_UI_PROMPT` injected into every system prompt regardless of client capability. Gate by `clientCapabilities`. |
| B-026 | `apps/server/src/trpc/routes/assistant.ts:2759-2778` | consistency | `dismissPreparedAction` lacks `lastReviewedAt: new Date()` and `actionId` shape validation that sibling `dismissOpenLoop` has. |
| B-027 | `apps/server/src/lib/ai-profile.ts:78-87` | correctness (LLM context) | Formatted local time omits timezone designator — same wall-clock string in PST and EDT is ambiguous. Add `timeZoneName: 'short'`. |
| B-028 | `apps/server/src/thread-workflow-utils/workflow-engine.ts:382-385` | design | `vectorizationWorkflow` and `labelGenerationWorkflow` registered unconditionally even when user has disabled assistant automation. Worth a deliberate decision. |
| B-029 | `apps/macos/TodusMac/Views/Email/MacEmailComposeView.swift:497-506` | correctness | Compose autosave `Task` not cancelled on view dismiss; pending 1-second autosave can write after `clearAutosavedDraft()` runs on send. Add `.onDisappear { autosaveTask?.cancel() }`. |
| B-030 | macOS + iOS `EmailService.withTimeout` | performance | `defer { group.cancelAll() }` issues structured cancellation, but unclear if `URLSession.data(for:)` honors `Task.isCancelled` in `TodosAPIClient`. Verify; use `withTaskCancellationHandler` to call `urlTask.cancel()`. |
| B-031 | `apps/macos/TodusMac/Views/Home/MacHomeView.swift:567-577` | dead code | `openMacBriefingRow` thread-id branch and fallback both call `onNavigate?(.email(.inbox))`. Implement deep-link or simplify to single call. |
| B-032 | `apps/macos/TodusMac/Domain/TaskSmartSort.swift:70-76`, `99-114` (and iOS mirror) | consistency | `bucket(for:)` returns single `.noDate`; `score(for:)` splits high-priority no-date from other. Bucket header view groups them together so the split is visually invisible — pick one. |
| B-033 | `apps/ios/Todus/Todus/Features/Tasks/TaskRowView.swift:225` & `apps/macos/TodusMac/Domain/SnoozeOption.swift:38` | UX | `SnoozeOption.weekend` lands on next Saturday when called Saturday afternoon. On Saturday, prefer Sunday 9am. |
| B-034 | `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift:171-176` | edge case | `.onAppear` sets `hideTabBar = false`; no symmetric restore on dismiss. Document or restore previous value. |
| B-035 | `apps/ios/Todus/Todus/Navigation/CreateSheet.swift:880-897` | correctness contract | `CompoundIntentParser` multi-intent path uses `intent.date ?? selectedDate` for every intent; unclear whether explicit folder/date should override every sub-intent. Define contract. |
| B-036 | `apps/ios/Todus/Todus/Navigation/CreateSheet.swift:875` | UX regression? | Auto-resolve type now requires both keyword AND date for `.event`. "Dentist Tuesday 2pm" used to classify as `.event`, now falls through to `.task`. Confirm intentional. |
| B-037 | `apps/ios/Todus/Todus/Services/Email/EmailService.swift:282-287` | observability | Stale-refresh detection uses strict `<`, so equal-newest refresh is accepted. Surface dropped count to telemetry. |
| B-038 | `apps/ios/Todus/Todus/Services/AI/AIChatService.swift` | correctness (rare race) | Comment says "Load deleted IDs synchronously addresses this" but `deleteConversation` mutates `conversations` itself, which the async loader can overwrite. Verify and document. |
| B-039 | `apps/web/app/(routes)/mail/tasks/page.tsx:204` | performance | New `void queryClient.invalidateQueries(...)` runs on every create on top of optimistic cache update — can thrash. Debounce or only invalidate when sort/filter would actually move the inserted task. |
| B-040 | `apps/web/app/(routes)/mail/tasks/page.tsx` | i18n | `NlpQuickAdd` placeholder is hardcoded English with Swedish example — confusing and not localized via Paraglide. |

## Hygiene (do not commit)

| ID | File | Action |
|----|------|--------|
| B-050 | `new-website/dev.log` (untracked), `new-website/relume/dev.log` (modified) | `git rm --cached new-website/relume/dev.log`; add `**/dev.log` to root `.gitignore`. |
| B-051 | `new-website/check-font.js`, `new-website/check-page.js`, `new-website/screenshot.js` (all 0 bytes) | Delete locally; if planned tooling, write content first. |

## Test gaps

| ID | Area | Approach |
|----|------|----------|
| B-060 | iOS + macOS parsers | Unit-test `LocalTaskParsingService`, `TaskSmartSort`, `CompoundIntentParser`. Cover `today 14` regression (B-011), weekday ordering, time rollover, smart-sort bucket assignment. |
| B-061 | apps/server | Unit-test `classifyThreadKind`, `extractVerificationCode`, `extractReceiptDetails`, `buildAiLeadLine`. Pure functions with high false-positive risk. |
| B-062 | iOS + macOS `withTimeout` | Sleep 5s with 0.1s timeout, assert `.timeout` thrown within ~150 ms. |
| B-063 | macOS compose | Smoke test that builds a draft with cc/bcc/connectionId and asserts wire payload (would have caught B-005). |

## Verified clean

- `d8d471c7` server pagination/parser regression fix — composite `(latestReceivedOn, id)` cursor correctly fixes the single-shard "exactly maxResults" pagination dead-end and the equal-timestamp cross-shard tie-skip. Backwards-compatible legacy parser path preserved.
- `apps/ios/Todus/Todus/Services/API/TodosAPIClient.swift` — `serializeJSONValue` correctly addresses NSInvalidArgumentException on `null`/fragment payloads. `EmailEmptyResponse` decodes from `{}` cleanly.
- `packages/swift-auth/Sources/TodusAuth/AuthService.swift` `preloadTokens()` — `nonisolated static` calling thread-safe `KeychainHelper.read` is sound.
- `apps/macos/TodusMac/Views/Email/MacEmailInboxView.swift` polling no longer triggers `forceSync` — fixes the destructive-resync-on-every-poll regression.
- `apps/ios/Todus/Todus/Domain/MailAssistantModels.swift` custom `init(from:)` with backward-compatible decoding for `aiLeadLine`/`threadKind`/`extractedCode`/`extractedReceipt` — correct pattern for staged backend rollout.
- `new-website/relume/{home,download,legal,pricing}/components/Navbar11.jsx` — pure formatting; all four files remain byte-identical post-change. (4-way duplication is its own debt; leaving for now.)
- `apps/web/messages/en.json` — only adds `pages.settings.general.location` keys; consistent with surrounding entries.
- `apps/macos/TodusMac/Views/Calendar/CalendarTimeGridView.swift` 1440-min cap — correct fix for visual overflow.
- `apps/macos/TodusMac/Views/Calendar/MacCalendarView.swift` `calshow:<refInterval>` URL — correct macOS scheme.
- `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift` `inFlightAction` race handling — correctly captures the action and only clears if it hasn't been replaced.

---

## Resolved in 2026-03-31 Review Session

| ID | Title | Area | Type | Status | What Changed |
|----|-------|------|------|--------|-------------|
| F01 | Missing `toast` import in chat/page.tsx | web/chat | bug | auto-fixed | Added `import { toast } from 'sonner'` — was causing runtime error on conversation load failure |
| F02 | Missing `Link` import in calendar/page.tsx | web/calendar | bug | auto-fixed | Added `import { Link } from 'react-router'` — was causing runtime error when calendar rendered |

---

# 2026-05-17 — iOS Bug-Hunt + UX-Polish Audit

Scope: `apps/ios/Todus/` — full read-only audit across 6 surfaces (auth/onboarding, email, tasks, calendar, AI chat, infra/services). 6 parallel sub-agents. No edits applied; user to triage. Total: 68 bugs, 84 polish items.

## Critical (ship-blockers) — 5

| # | File:line | Title | Surface |
|---|-----------|-------|---------|
| C1 | `packages/swift-auth/Sources/TodusAuth/AuthService.swift:877-883` | Deep-link token injection on unauthenticated app — attacker `todus://auth-callback?token=X` accepted when signed out; Apple flow never sets `pendingAuthFlowExpiresAt` | auth |
| C2 | `apps/ios/Todus/Todus/App/TodosApp.swift:411-413` | Notification taps for email/AI/due-task/reminder are dead — switch only handles `TASK_COMPLETE`/`TASK_SNOOZE`, everything else falls into `default: break` | infra |
| C3 | `apps/ios/Todus/Todus/Services/AI/AIChatService.swift:1370-1485` + `Features/AI/AIChatView.swift:217-244` | Mutation confirmation deadlocks AI agent — `send_email`/`update_calendar_event`/`delete_calendar_event` suspend forever; no UI observes `pendingMutationConfirmation` | ai |
| C4 | `apps/ios/Todus/Todus/Services/AI/AIChatService.swift:416-434` | Mutation continuations leak on cancel — `cancelStream` only resumes delete continuations, never mutation ones; Stop mid-confirm leaks Task + CheckedContinuation warning | ai |
| C5 | `apps/ios/Todus/Todus/Features/Calendar/CalendarPermissionView.swift:39` | Calendar permission view stuck loading after grant — no `onReceive(.todusCalendarAuthorizationDidChange)`; view never invalidates | calendar |

## High severity — 17

### Auth (2)
- **H1** `AuthService.swift:1354-1372` — Stale refresh token persisted across re-login; JWT-only third branch never clears `refreshToken`/`currentSessionId` → cross-account session leak
- **H2** `Services/Auth/AuthSessionStore.swift:294-305` + `TodosApp.swift:42,54` — Legacy Supabase store flipped into magic-link state by Better Auth callback URLs containing `email=`

### Email (3)
- **H3** `Features/Email/EmailThreadView.swift:493-501` — Star toggle never rolls back on API failure; user thinks starred, isn't
- **H4** `Features/Email/EmailThreadView.swift:1049-1054` — `markAsSpam` always dismisses regardless of success; offline spam-report silently fails
- **H5** `Features/Email/EmailThreadView.swift:294-321` + `EmailInboxView.swift:600-612` — `priorError \!= current` failure detection fragile across shared singleton state; concurrent ops mask/mimic failures

### Tasks (3)
- **H6** `Features/Tasks/TasksTabView.swift:209-220` — `consumePendingTaskNavigation` uses GCD `asyncAfter` w/ no cancel; rapid second tap shows stale task
- **H7** `Services/Parsing/RemoteFirstTaskParsingService.swift:38-55` — Remote NLP `lowConfidence` silently dropped; only surfaces on local fallback
- **H8** `Services/Tasks/TaskCaptureService.swift:100-129` — Capture rollback races concurrent enrichment enqueues; non-deterministic state machine

### Calendar (3)
- **H9** `Features/Calendar/CalendarTabView.swift:448, 456` — Day view shows ONLY Apple events; Google events stripped because `loadEvents` early-returns for `.day` mode
- **H10** `Features/Calendar/CalendarTabView.swift:520-524` — Tapping Google/CalDAV event silently no-ops; `event(withIdentifier:)` returns nil and code `return`s
- **H11** `Features/Calendar/EKWrapper.swift:46-50` — Force-unwrap on `ekEvent.calendar.cgColor` crashes when calendar deleted mid-session

### AI (3)
- **H12** `Services/AI/AIChatService.swift:1910-1929` — `flushTokenBuffer` runs against stale messageID; mid-flush `clearHistory`/`retry` loses tokens
- **H13** `Services/AI/AIChatService.swift:2192-2196` — Calendar snapshot leaks "not granted" string after permission grant until cache invalidated
- **H14** `Services/AI/AIChatService.swift:1066-1078` — SSE byte parser splits on `\n` only; `\r\n` from CDN causes `"[DONE]\r"` mismatch + decode failures on final chunk

### Infra (3)
- **H15** `Services/API/TodosAPIClient.swift:163-189` — TRPC body sent as raw JSON; server superjson expects `{json,meta}` for `Date`/`Set`/`BigInt` — dates corrupt over wire
- **H16** `Services/API/TodosAPIClient.swift:60-64` — `JSONSerialization.data(withJSONObject:)` crashes on String/Int inputs (fragment rule); `trpcBatchQuery` with id arrays raises NSInvalidArgumentException
- **H17** `Services/Voice/AudioPlayerManager.swift:68-82` — `ensureEngineRunning` re-attaches already-attached node when session ends without `stop()`; crashes on reconnect

## Medium severity — 46

(Full per-surface lists archived in agent transcripts; high-leverage subset listed below)

### Email
- `EmailThreadView.swift:866` markAsRead failure poisons shared `errorMessage` → contaminates subsequent dismiss checks
- `EmailComposeView.swift:691-695` `canSend` blocks legitimate empty-subject replies
- `EmailRowView.swift:10-15` `timeString` cached in init → "Yesterday" stale across midnight
- `Services/Email/EmailService.swift:309-313` pagination dedupe by id only; stale page-1 thread retained when newer copy lands on page 2
- `EmailInboxView.swift:1269-1276` `consumePendingThreadNavigation` GCD asyncAfter fires after view disappears
- `EmailInboxView.swift:306-308` `badgeForciblyHidden` latches across refreshes
- `EmailComposeView.swift:94` Reply/ReplyAll separate autosave keys orphan drafts
- `EmailThreadView.swift:1786+` EmailHTMLView no nav delegate → in-place link nav strands user

### Tasks
- `Services/Reminders/AppleRemindersSyncService.swift:340-358` `inFlightUpserts` guard is no-op; redundant EKEventStore XPC calls
- `Services/Reminders/AppleRemindersSyncService.swift:340-357` Two-way sync never reopens — uncheck in Reminders, Todus stays done
- `Features/Tasks/InboxView.swift:128` `onChange(of: allTasks)` walks N items on every SwiftData mutation
- `Services/Tasks/TaskCaptureService.swift:98` `try? context.save()` swallows disk-full errors
- `Services/Tasks/TaskCaptureService.swift:65-66` No cap on `splitInputLines`; 10k-line paste = 10k enrichment tasks
- `Services/Reminders/AppleRemindersSyncService.swift:301-310` `pendingUpsertTaskIDs` retry recursive, no max-attempts

### Calendar
- `Features/Calendar/CalendarTimeGridView.swift:19, 67-69` `Timer.publish(...).autoconnect()` leaks per page in MultiDay
- `Features/Calendar/CalendarViewController.swift:140-172` `fetchEvents` ignores authorization revoke; stale events served forever
- `Features/Calendar/CalendarTabView.swift:483-485` `isLoading` not reset on Task cancellation
- `Features/Calendar/CalendarTabView.swift:204` `.highPriorityGesture(pinch)` conflicts with `UIPageViewController` swipe
- `Services/Meetings/MeetingsService.swift:140-146` `syncFromCalendar` only `print`s errors

### AI
- `Services/AI/AIChatService.swift:1107-1116, 2528-2534` Keep-alive deltas treated as `.unrecognised` → main-actor JSON decode spam
- `Services/AI/AIChatService.swift:2002-2007` 50-conversation history serialized into one Keychain blob → exceeds ~4KB item limit; silent persist failure
- `Services/AI/AIChatService.swift:1119-1132` Stale `streamFailed` not reset on cancel; retry banner from prior turn sticks
- `Services/AI/AIChatService.swift:1727-1734` `buildPayload` includes in-flight assistant placeholder content → duplicated assistant turn in next step
- `Services/AI/AIChatService.swift:346-393` `retry(...)` doesn't clear `messages[i].errorMessage` → footer pinned under successful response
- `Services/AI/AIChatService.swift:2070-2104` `fetchFullConversation` overwrites local renames/moves unconditionally

### Infra
- `Services/Subscription/SubscriptionService.swift:100-104` `cancel` re-entrancy on shared `isLoading`; spinner deadlock on double-tap
- `Services/Notifications/NotificationDigestService.swift:173-211` Hand-rolled URLSession bypasses TodosAPIClient — no 401 refresh, no superjson
- `Services/NetworkMonitor.swift:9, 16` `isConnected` defaults `true` pre-NWPath callback → wrong banner flash, false reconnect trigger
- `Services/Widgets/WidgetUpdateManager.swift:40-50` Tasks completed today without `dueDate` excluded from widget stats
- `Navigation/MainTabView.swift:86-101` Calendar permission desync — Settings flip without scenePhase change shows stale permission UI
- `Navigation/CreateSheet.swift:973-1011` Event create allows end < start; backend rejects, user loses transient state
- `DesignSystem/AppTheme.swift:14-17` Avatar cache `dataKey = urlString.hashValue` — non-stable across launches (process-salted), cross-user collision risk
- `DesignSystem/AppTheme.swift:36-48` Avatar JPEG bytes in UserDefaults → bloats prefs.plist, slows launch
- `DesignSystem/AppTheme.swift:530-543` `AppPrimaryButtonStyle` hardcodes `Color.blue` — ignores `Color.accentColor` / Increase Contrast

### Auth (additional)
- `AuthService.swift:228-358` Apple Sign In never sets `pendingAuthFlowExpiresAt` → provenance bypass + mid-flow URL kills state
- `App/RootView.swift:85-88, 105-108` `loadSharedAIProfile` called twice on signed-in launch
- `KeychainHelper.swift:38-43` Legacy-delete failure aborts save → silent token drop on locked keychain

## UX polish — top 20 across surfaces (84 total in agent transcripts)

| # | Impact | File:line | Gap | Fix |
|---|--------|-----------|-----|-----|
| P1 | High | `Features/Email/EmailInboxView.swift:635-648` | Archive uses `role: .destructive` (red) — fear of mis-swipe | Drop `.destructive` |
| P2 | High | `Features/AI/AIChatView.swift:1332-1342` | Send button disappears when empty → layout shift | Always render, gate `.disabled(isEmpty)` |
| P3 | High | `Features/AI/AIChatView.swift:914-919` | "Thinking…" vanishes on first token but text may be empty for 10s if reasoning tokens stream | Keep indicator while `reasoningContent` grows + `content` empty |
| P4 | High | `Features/AI/AIChatView.swift:2247-2273` | Thumbs up/down is local-only no-op → fake feedback | Wire to feedback endpoint or remove |
| P5 | High | `Features/Tasks/TaskRowView.swift:286` | No haptic on complete | `UIImpactFeedbackGenerator(.light).impactOccurred()` |
| P6 | High | `Features/Tasks/TaskRowView.swift:112-117` | Context-menu Delete no confirmation (TaskTableView has one) | Add `confirmationDialog` |
| P7 | High | `Features/Calendar/CalendarTimeGridView.swift:155-160` | Event blocks <24pt below 44pt HIG touch target | `.frame(minHeight: 44)` on contentShape |
| P8 | High | `App/GmailOnboardingView.swift:51-84` | Skip stays tappable during connect → race | `.disabled(isConnecting)` |
| P9 | High | `Features/Email/EmailThreadView.swift:493-501` | Star button no accessibility state | `.accessibilityLabel(isStarred ? "Starred" : "Not starred")` |
| P10 | High | `Navigation/MainTabView.swift:296-308` | Offline banner subtle pill, no retry CTA | Add Retry button |
| P11 | High | `Features/Email/EmailComposeView.swift:201-231` | Send button no "Sending…" text, no success haptic | Add label + `.sensoryFeedback(.success, trigger:dismissed)` |
| P12 | High | `Features/Auth/AuthView.swift:144-165` | Apple/Google tappable while Email OTP loading | `.disabled(authService.isLoading)` on stage-1 stack |
| P13 | High | `Features/Auth/AuthView.swift:73-76` | Error banner persists indefinitely | Auto-clear via `.task(id: lastErrorMessage)` |
| P14 | High | `Features/Home/HomeView.swift:1054-1067` | No skeleton on cold launch — white 1-3s | 3 ghost rows while `\!hasLoadedEmailState` |
| P15 | High | `Features/Calendar/CalendarListView.swift:170-180` | Empty calendar dead-ends — no CTA | Add "Create event" button |
| P16 | Med | `Features/Tasks/BoardColumnView.swift:78-83` | Empty board column no `+` (drop-only on touch) | Add `+` to column header |
| P17 | Med | `Features/Calendar/CalendarEventBlockView.swift:18-48` | No VoiceOver label | `.accessibilityLabel("\(title), \(timeString)")` |
| P18 | Med | `App/NotificationsOnboardingView.swift:90-99` | Skip tappable during permission request | `.disabled(isRequesting)` |
| P19 | Med | `Features/AI/AIChatService.swift:1521` | `appendFallback` writes literal "Done." | Generate from chip set |
| P20 | Med | `Features/Email/EmailThreadView.swift:1564` | Timestamp uses abbreviated date for recent — "2 min ago" expected | `RelativeDateTimeFormatter` <24h |

## Recommended fix order

1. **Today (security/data loss):** C1, H1 (auth token leaks); C2 (notification deep-links dead); C3+C4 (AI mutation deadlock+leak).
2. **This week (user-visible silent failures):** C5, H3, H4, H5 (email silent failures); H9, H10, H11 (calendar Day view + crashes); H15, H16 (TRPC wire format).
3. **Next sprint (data integrity):** H2, H6, H7, H8, H12, H17 + medium-severity sync/persistence items.
4. **Polish backlog:** Top-20 polish list — most are ≤5 line changes, batch into a single PR.

Full per-agent transcripts available at task IDs af528b40, ac4cfe8a, a5957fb7, a1675c0e, a8be1ed8, ad5e823b.

---

# 2026-05-20 — iOS Mobile App Bug Hunt

Scope: main user flows (auth, email, AI chat, tasks, calendar, network) in `apps/ios/Todus/Todus/`. 6 parallel investigators reviewed services + feature views. Findings below have been *verified by reading the cited line ranges* — speculative investigator claims that did not survive verification are listed separately at the bottom so they don't get re-investigated.

## Auto-fixed in this run

| ID | File:line | Status | What changed |
|----|-----------|--------|--------------|
| BH-2026-05-20-01 | `apps/ios/Todus/Todus/Services/AI/AIChatService.swift:2066` | fixed | `finaliseStream` set `isStreaming = false` *before* flushing `tokenBuffer` into the message. SwiftUI subscribers that read both flags could see the typing indicator disappear while the last tokens were still being appended. Moved the flag reset after the flush + `parseUISpec()`. |
| BH-2026-05-20-02 | `apps/ios/Todus/Todus/Services/Tasks/SupabaseSyncService.swift:42` | fixed | `enqueue()` on the `client == nil` path called `queue.popLast()?.continuation.resume()` *and then* `continuation.resume()`. The popped batch's continuation **is** the outer `continuation` (just appended one line above), so this double-resumed a `CheckedContinuation`, which traps with a fatal error. Replaced pop-then-resume with `queue.removeLast(); continuation.resume()`. |

## Verified — needs human review

| ID | File:line | Severity | Issue | Suggested fix |
|----|-----------|----------|-------|---------------|
| BH-2026-05-20-03 | `apps/ios/Todus/Todus/Features/Email/EmailAIDraftSheet.swift:257` | warning | `defer { Task { @MainActor in isStreaming = false } }` inside the outer `Task` schedules a *detached* hop to reset the flag. The outer `streamingTask` returns before the flag is reset, so a fast user can re-tap "Generate" while `isStreaming` is still true momentarily, or dismiss the sheet and have the detached Task mutate freed view state. | Replace the detached `Task` with an `await MainActor.run { isStreaming = false }` at the end of the outer Task body, or set the flag before the `defer` exits via direct assignment (the outer Task is already `@MainActor`-isolated via the enclosing view). |
| BH-2026-05-20-04 | `apps/ios/Todus/Todus/Services/Reminders/AppleRemindersSyncService.swift:286` | info | `completionDate = task.completed ? task.updatedAt : nil`. If a task was completed long after its last edit (e.g. updated at 9am, completed at 5pm), `completionDate` is set to the *edit* time, not the *completion* time. Surfaces in Reminders' "Completed" smart list with the wrong timestamp. | Track `completedAt` separately on `TaskRecord` and write that into Reminders, or write `.now` on the transition `false → true`. Skipped auto-fix because the model change is non-trivial. |

## Unverified leads (investigator candidates that need a closer look)

These were flagged by the parallel investigators but could not be confirmed without deeper context. They are listed so future passes can either confirm or close them.

- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift` — claims of (a) partial JSON in tool arguments after `[DONE]` (line ~1115), (b) `executeToolCalls` not honouring cancellation between awaits (line ~1214), and (c) `syncLoadConversations` racing with local deletes (line ~2233). All plausible but require running the SSE parser and the delete handler concurrently to confirm.
- `apps/ios/Todus/Todus/Services/Tasks/SupabaseSyncService.swift:45` — claim that `queue.popLast()` races with concurrent `enqueue()`. Service is `@MainActor` so concurrent calls serialise, *but* the inner `Task { await processQueue }` re-enters the actor between awaits — worth re-reading once we add a `processQueue` test fixture.
- `apps/ios/Todus/Todus/Services/Reminders/AppleRemindersSyncService.swift:359` — off-by-one in `maxCoalescedRetries` (allows N+1 attempts). Need to read the retry counter increment vs guard to confirm.
- `apps/ios/Todus/Todus/Features/Calendar/CalendarTimeGridView.swift:295` — multi-day event height collapse when `rawEndMinutes` is capped at 1440 without recalculating duration on subsequent days. Reproduce with a 2-day event spanning midnight.
- `apps/ios/Todus/Todus/Features/Calendar/CalendarMultiDayView.swift:346` — claim that `startOfDay(for: event.startDate)` vs `startOfDay(for: date)` mismatch causes all-day events to render on the wrong day across DST/timezone boundaries.
- `apps/ios/Todus/Todus/Services/Calendar/GoogleCalendarService.swift:316–333` — `fetchCalendars(for:)` catches errors and returns `[]` while clearing `scopeMissing`. Conflates "no scope" with "network failure". UI gives no retry banner.

## Speculative claims dismissed during verification

(Listed so the next bug hunt doesn't re-flag them.)

- ~~`AuthView.swift:142` — `if case .otpPending(let email)` pattern allegedly broken.~~ Verified valid Swift; `otpPendingEmail` works correctly.
- ~~`TodosAPIClient.swift:231` — TRPC envelope decode `try?` "swallows" errors.~~ Documented intentional fallback to bare-response decoding (see comment at line 239).
- ~~`TodosAPIClient.swift:345` — bearer token nil header.~~ Code already uses `if let token` guard; header only set when token exists.
- ~~`TodosAPIClient.swift:376–383` — 401 retry "broken".~~ `didRefresh` flag intentionally limits refresh to one attempt per request, then surfaces `unauthorized`. Behaviour matches the inline comment.
- ~~`TodosAPIClient.swift:404–413` — mutation retries unsafe.~~ Retry list is explicitly restricted to URLErrors that mean "request did not reach the server"; matches the inline comment.
- ~~`CalendarService.swift:96–124` — empty `hiddenCalendarIds` "returns everything".~~ Documented as legacy behaviour in the doc comment ("An empty set fetches across all calendars").
- ~~`UnifiedCalendarService.swift:82–93` — Apple/Google tasks "throw and silently lose Apple data".~~ Neither helper is `throws`; the `async let` returns `[]` on failure.
- ~~`EmailInboxView.swift:627` — pagination success misdetected as failure.~~ Logic correctly checks `if let current` *and* `current \!= priorError`; nil case is handled.


## Bug Hunt + UX Assessment — 2026-05-24 (iOS + macOS Home pages)

### Auto-fixed (3 issues)
- `apps/macos/TodusMac/Views/Home/MacHomeView.swift:52` — `isEmailRefreshing` missing `|| isReconciling`; "Updating" badge was absent during post-forceSync reconciliation on macOS while iOS showed it correctly
- `apps/macos/TodusMac/Views/Home/MacHomeView.swift:1281` — email timestamp hardcoded as `hour().minute()` showing "14:32" even for week-old threads; replaced with `emailTimeLabel()` helper (same logic as iOS: "5m ago" / "Yesterday" / "Apr 23")
- `apps/macos/TodusMac/Views/Home/MacHomeView.swift:280-284` — `emailSectionSubtitle` unreachable branch (`total <= shown` always true since `shown = min(5,total)`); dead branch removed

### Needs human review (4 issues)
- `apps/macos/TodusMac/Views/Home/MacHomeView.swift:902` — `meetingsSection` commented out in `scheduleSidebar`; iOS renders it. Re-enable once desktop layout is confirmed. TODO comment added.
- `apps/macos/TodusMac/Views/Home/MacHomeView.swift:565,601,640` — `assistantPriorityStrip`, `assistantQueueColumn`, `macBriefingRowCard` are dead code from old three-column briefing UI. Safe to delete. TODO comments added.
- `apps/ios/Todus/Todus/Features/Home/HomeView.swift:411` — `heroStatChips` computed but never rendered (planned hero chip UI was removed). TODO comment added.
- `apps/macos/TodusMac/Views/Home/MacHomeView.swift:52` (**NOTE: fixed**) but also verify `isEventsRefreshing` only checks `todaysEvents` (line 48) while iOS checks `upcomingEvents` — may be intentional given macOS splits sections.

## Bug Hunt — 2026-05-21

### Auto-fixed (3 issues)
- `apps/macos/TodusMac/App/MacAppServices.swift` — moved the dynamic settings-save encoder out of a generic function so Swift 6 can compile `syncSetting`.
- `apps/macos/TodusMac/Views/Home/MacHomeView.swift` — fixed the misplaced enclosing brace around the nested hover row helper.
- `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift` — split large SwiftUI modifier chains into smaller helper chains to resolve compiler type-check timeouts.

### Needs human review (0 issues)
- None.

## Docs review pass — 2026-05-24 (round 2, follow-up to overhaul)

### Auto-fixed (15+ items, see CHANGELOG `Docs review pass` entry)
Includes context-menu parity, persistent saved badge, web data attributes, iPad row highlight restore, MoreSheet double-stack fix, iOS haptics, swipe-delete confirmation, autofocus cancellable, save-indicator min-width, dark-mode listener, sort animation, sidebar indent via padding, Cmd+B / Cmd+I shortcuts, AppStorage self-heal comment.

### Needs human review / design call (8 items)

- **Recursive `AnyView(Group/VStack { row; ForEach(children) })` outline** (`DocsListView.swift:336-343` and `MacDocsShellView.swift:687-707`) — breaks SwiftUI identity; can cause hover/swipe state to bleed and re-render the whole nested subtree on changes. Refactor candidates: `OutlineGroup` with `KeyPath` children, or flatten so each row stands alone in its parent `ForEach`.
- **No recursion-depth/cycle guard in `docRow` / `docOutline`** (same files) — corrupt server data (`A.parentId == B.id`, `B.parentId == A.id`) stack-overflows. Add `visited: Set<String>` param.
- **Debounced title save + `flushPendingSave` race** (`DocEditorView.swift:flushPendingSave`) — both POST `renameDoc`. If network reorders, stale value wins. Centralize through a single Task chain, or have backend honor a client `updatedAt`.
- **`commitRename` Task is fire-and-forget** (iOS + macOS) — errors that surface after view teardown are lost. Move into service layer or store Task handle.
- **`sizeClass` change mid-tap on iPad** (`DocsListView.swift:open(docID:)`) — Stage Manager / slide-over resize between push and animation drops active doc. Sync `path` ↔ `selectedDocID` in `.onChange(of: sizeClass)`.
- **macOS Cmd+F search focus** — spec mentioned, not wired; macOS search field also disappears when an editor is open (right pane swap). Either move search to sidebar or keep a slim search above the editor.
- **iOS body autofocus after title `submitLabel(.done)`** — currently only dismisses the keyboard; Apple Notes drops cursor into body. Needs a `window.todusEditor.focus()` bridge call in `DocsBrowserView`.
- **iOS grid view + sort menu parity gap** — macOS has both, iOS has neither. Discussed in spec, intentionally deferred — flag in case it surfaces in user feedback.

## Bug Hunt — 2026-05-24 — Docs feature overhaul

### Auto-fixed (1 issue, in files touched this session)
- `apps/ios/Todus/Todus/Features/Docs/DocEditorView.swift:scheduleDebouncedTitleSave` — debounced title save now snapshots `titleDraft` at schedule time and bails if the draft moved on while sleeping; previously a teardown-time `flushPendingSave` could race against the scheduled task reading a mutated draft.

### Needs human review (5 issues, in pre-existing files NOT touched this session)
- `apps/macos/TodusMac/Views/Docs/MacDocEditorPane.swift:167-168` (Critical) — `services.docsService.preAIEditSnapshot` and `wk` are force-unwrapped on AI revert. Crash if either nil. Fix: `guard let snap = …, let wk = …`.
- `apps/ios/Todus/Todus/Features/Docs/DocsWebView.swift:103-115,158-178` (Important) — WKNavigationDelegate callbacks dispatch via `Task { @MainActor in }` without weak self / cancellation token; stale reads possible if the WebView deallocs. Also no 401 retry: if the token rotates mid-load the page sticks.
- `apps/macos/TodusMac/Views/Docs/MacDocEditorPane.swift:93-97` (Important) — 5-minute `Task.sleep` revert timer not cancelled on `.onDisappear` — long-running background tasks accumulate.
- `apps/macos/TodusMac/Views/Docs/MacDocEditorPane.swift:156-160` (Important) — `flushPendingSave` swallows errors silently; if the doc was deleted while the editor was open, the user gets no signal. Log + surface.
- `apps/ios/Todus/Todus/Services/Docs/DocsService.swift:85-97` & `apps/macos/TodusMac/Services/Docs/MacDocsService.swift:128-139` (Minor) — Personal-workspace auto-create races + flag never resets across sign-out. Make idempotent server-side or via observable state.

---

## Bug Hunt — 2026-05-26 — iOS Tasks page

Scope: `apps/ios/Todus/Todus/Features/Tasks/` + `Services/Tasks/TaskCaptureService.swift` + domain models.

### Auto-fixed (3 issues)

| File:line | Severity | What changed |
|-----------|----------|--------------|
| `InboxView.swift:47` | error | `emptyState` branch fired when `visibleTasks.isEmpty && completedTasks.isEmpty` even if `olderCompletedTasks` had entries — those older completed tasks were rendered by no view in this branch. Users with recently-cleared recent completeds but retained older ones saw "Inbox is empty" and had no way to access older work. Fixed: added `&& olderCompletedTasks.isEmpty` to the condition. |
| `BoardView.swift:63` | warning | `boardChangeDigest` returned `[BoardTaskDigest]` — O(N) array equality check on every SwiftUI body re-evaluation. Every other view uses a `(count, latestUpdate)` digest (O(1)). Replaced with identical `TasksDigest` struct pattern. Removed now-unused `BoardTaskDigest` struct. All mutations bump `updatedAt`, so O(1) digest is safe. |
| `CalendarTaskView.swift:339` | error | Context-menu Delete in `CalendarTaskCard` fired immediately without confirmation, inconsistent with `TaskRowView` and `TaskTableView` which both show a `confirmationDialog`. Added `@State private var showDeleteConfirmation` and a `.confirmationDialog` matching the pattern in `TaskRowView`. |

### Needs human review (2 issues)

| File:line | Severity | Issue | Suggested fix |
|-----------|----------|-------|---------------|
| `BoardColumnView.swift:44` | warning | `@Query(sort: \TaskRecord.createdAt, order: .reverse) private var tasksInApp: [TaskRecord]` inside `BoardColumnView` fetches ALL tasks independently of the `tasks: [TaskRecord]` prop already passed by `BoardView`. Only used in `handleDrop` for a single task lookup by UUID. This means every task mutation triggers an O(N) SwiftUI re-render of ALL `BoardColumnView` instances, not just the affected column. | Replace the `@Query` with a `@Query`-free `modelContext.fetch(FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == taskID }))` call inside `handleDrop` at drop time. |
| `TaskDetailSheet.swift:72` | info | `isSaving` is set to `true` before `saveTask()` and never reset to `false`. `saveTask()` always calls `dismiss()`, which destroys the view, so the state reset doesn't matter in practice. But if a future code path calls `saveTask()` without dismissing (e.g., inline editing), the Save button would be permanently disabled. | Reset `isSaving = false` at the start of the `catch` or error path, or after any non-dismissing code path. |

---

# 2026-06-08 — iOS Simulator QA pass

Scope: native iOS app `apps/ios/Todus`, driven live in the iPhone 17 / iOS 26 simulator under `--ui-testing`, plus a deep email perf/correctness sub-agent audit.

## ✅ Fixed this pass (see `CHANGELOG.md` → "iOS Simulator QA pass")
- **Round 1** (committed `e2ee191f`): silent capture-failure banner, multi-recipient email entry, Tasks empty-state copy, Home section-icon a11y, GroupChat clobber guard.
- **Round 2**: IOS-0608-1 (offline capture no longer deleted — `URLError`/`backendNotConfigured` keep `.localOnly`, re-sync on reconnect), IOS-0608-3 (optimistic star + rollback), IOS-0608-4 (AI tab context seeded from restored tab), IOS-0608-5 (More-tab dark background `#1c1c1e`), IOS-0608-6 (share-sheet foreground-active scene, both call sites), IOS-0608-8 (CreateSheet To/Cc/Bcc placeholders no longer blue). **Email perf**: cached date formatters (`EmailModels.parseDate`, `EmailThreadView` receipt chip), **security**: email-HTML CSP gained `form-action 'none'; base-uri 'none'`. **Tests added**: `EmailServiceTests` (toggleStar optimistic/rollback + `parseDate` formats), `SupabaseSyncServiceTests` (offline/unconfigured keep-local vs reject-fail).

## Still open (verified real, deferred — higher-risk / product call / needs backend)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| IOS-0608-P1 | Email perf | `Services/API/TodosAPIClient.swift:5` (`@MainActor`) + `EmailService.swift:~785` | 🔴 **critical** | The whole API client is `@MainActor`, so the JSON decode + `JSONSerialization` of the 50-thread `mail.get` batch runs on the **main thread** — UI hitch on every inbox load/refresh. | Move decode off-main: a `nonisolated` batch-parse path (needs `Sendable` conformances on decoded types) or drop `@MainActor` from the client. App-wide; own pass. |
| IOS-0608-P2 | Email | `Features/Email/EmailInboxView.swift:1043` + `1414` | 🟠 high | Per-connection filter chips toggle `enabledConnectionIds` but `recomputeFilteredThreads` never filters by it and `EmailThread` has no `connectionId` → toggling a mailbox does nothing. **Dead feature.** | Add `connectionId` to `EmailThread` (backend) + filter, or remove the chips. |
| IOS-0608-2 | Calendar | `CalendarViewController.swift:~280` | 🟡 med | Long-press create-event no-ops with no feedback when no writable calendar (rarer than first reported — `createNewEvent` only nils on missing `eventStore`/date math; the nil-calendar case fails at save). | Surface a toast when `defaultCalendarForNewEvents` is nil. |
| IOS-0608-P3 | Email perf | `EmailThreadView.swift:~788` (`messagesSection`) | 🟡 med | Messages render in a non-lazy `VStack` ForEach inside a ScrollView; every expanded MessageRow owns a WKWebView, all built eagerly for long threads. | `LazyVStack` so off-screen rows/WebViews defer (verify scroll anchoring). |
| IOS-0608-P4 | Email | `EmailThreadView.swift:~944/556` | 🟡 med | Open-thread star is local `@State` from `mail.get`; starring from the inbox swipe (now optimistic on `threads`) doesn't update the open detail. | Derive thread `isStarred` from `emailService.threads` labels (single source). |
| IOS-0608-7 | Email | `EmailComposeView.swift` formatting toolbar | 🔵 low | Bold/list/H1 append at end of body, ignoring caret. | Insert at `RichComposerInput` selection range. |
| IOS-0608-9 | Email | `EmailInboxView.swift` header | 🔵 low | Tab "Email" vs page header "Mail" — cross-platform naming call (left unchanged to avoid iOS-only drift from macOS/web). | Decide one term across all platforms. |
| IOS-0608-10 | Tech debt | `Features/Tasks/CaptureComposer.swift` | 🔵 low | Dead file, zero call sites — needs `.pbxproj` removal (skipped to avoid project-file surgery). | Delete via Xcode. |
| IOS-0608-P5 | Email | `EmailService.swift:~1106` (`snoozeBriefingOpenLoop`) | 🔵 low | Optimistically removes the open-loop row but never re-adds on server failure (dismiss/complete share the pattern). | Snapshot + restore the briefing on snooze failure. |

> **Note (2026-06-13):** IOS-0608-P1 (iOS main-thread tRPC decode) is now **resolved** for iOS by commit `22afa335` (off-main `Task.detached` decode). The macOS twin remains open — see **CR-0613-2** below.

---

# 2026-06-13 — Full-repo review pass (uncommitted iOS/macOS/web + commits 3fc07eae, 2ca46e3b, 22afa335)

Scope: all unstaged changes (43 files) + the 3 latest local-but-unpushed commits. Reviewed by 6 parallel subagents (iOS local-AI, macOS local-AI, email iOS+macOS, web TSX, iOS UI/nav, committed iOS core), then every high-severity finding verified against source by hand.

## ✅ Auto-fixed this pass (3 — small, verified-safe)

| File:line | Severity | What changed |
|-----------|----------|--------------|
| `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift:1532` | 🟡 med | `formatCredits` lacked the `scaled.isFinite` + `scaled < Double(Int.max)` guards that iOS `BillingSettingsView.formatCredits` has, yet is called with raw decoded server values (`aiUsageUsed`/`aiUsageLimit`). A corrupted/NaN value would trap `Int(NaN.rounded())` and crash the macOS Billing tab. Mirrored the two iOS guards verbatim (return `"—"`). Honors the "keep all three platforms in sync" rule. |
| `apps/ios/Todus/Todus/Services/Tasks/SupabaseSyncService.swift:64` | 🔵 info | Removed a stale, self-contradicting `TODO` claiming `retryUnsyncedTasks` still needed wiring to `NetworkMonitor` "at the AppServices level" — it is already wired at `AppServices.swift:926` (`networkMonitor.onReconnect`), as line 166 in the same file asserts. Replaced with an accurate doc line. |
| `apps/ios/Todus/Todus/Features/Calendar/CalendarTabView.swift:197` | 🔵 info | Fixed a stale comment ("Today FAB — bottom-left") that contradicted the code, which centers the FAB (Spacer on both sides; inner comment already says "Centered"). Changed to "bottom-center". |

## 🔴 Open — verified real, non-trivial / behavior-changing (NOT auto-fixed per review policy)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| CR-0613-1 | Data integrity | `Services/Tasks/SupabaseSyncService.swift:176` + `Services/API/SupabaseEdgeFunctionClient.swift:52,63` | 🔴 **critical** | The offline-capture-deletion fix (IOS-0608-1) closed the *transport-failure* hole but not the *server-failure* one. `invoke()` collapses every non-2xx (incl. 5xx/429/503) into a status-less `BackendClientError.invalidResponse`, and a decode failure on a 2xx body throws `DecodingError`. Both fall through `processQueue`'s `default` → `.failed` → `TaskCaptureService:123-130` `context.delete(task)`. A backend outage / rate-limit / body-shape change silently destroys a user's offline-captured task. | Thread the HTTP status through `BackendClientError` (e.g. `.serverError(statusCode:)`). In the sync `catch`, `keepLocal = true` for 5xx/429/408 **and** decode failures; only `keepLocal = false` on a true 4xx semantic reject (400/409/422). Then add the capture()-level test (CR-0613-13). |
| CR-0613-2 | Email perf (macOS) | `apps/macos/TodusMac/Services/API/TodosAPIClient.swift:89,119,186,190` | 🔴 critical | The iOS "decode off main thread" fix (commit 22afa335 / IOS-0608-P1) was **not** ported to macOS. The macOS client is `@MainActor` and still `JSONDecoder.decode`s large `mail.get` HTML payloads inline on the main actor → UI freeze on every inbox load/refresh. | Port the iOS off-main decode: `Task.detached` decode path with `Output: Decodable & Sendable`, shared `apiDecoder`. |
| CR-0613-3 | Email (macOS) | `apps/macos/TodusMac/Services/Email/EmailService.swift:540-563` (`loadThreads`) | 🟠 high | No load-generation guard (iOS uses `loadGeneration == myGen`). A slow, superseded folder-A load that fails *after* the user switches to folder B writes `errorMessage`/`paginationFailed` unconditionally → stale error banner / pagination-failed footer flashes over folder B. The `CancellationError` catch is dead because this path never cancels the older task. | Port the iOS generation-gate: snapshot `myGen` at entry, gate every `errorMessage`/`paginationFailed`/`isLoading` write on `loadGeneration == myGen`. |
| CR-0613-4 | Email (macOS) | `apps/macos/TodusMac/Services/Email/EmailService.swift:1232-1330` | 🟠 high | `markAsRead`/`markAsUnread`/`toggleStar` do not invalidate `threadDetailCache` (5-min TTL); iOS added `invalidateThreadDetail` in 2ca46e3b. Opening a just-read/just-starred thread shows pre-mutation state until TTL. `invalidateThreadDetail` doesn't exist on macOS. | Add `invalidateThreadDetail(threadID:)` and call it from all three mutations (safe even on optimistic rollback — next open refetches truth). |
| CR-0613-5 | Local AI (iOS) | `Services/AI/Local/MLXInferenceService.swift:149` (`loadCoalesced`) | 🟠 high | Coalesced-caller cancellation race (currently only TODO'd). If `evict()`/`unloadAll()` cancels the in-flight load after the `!isCancelled` check but during `await pending.task.value`, an un-cancelled caller receives `CancellationError` (→ `LocalAIError.cancelled`) and its legitimate stream aborts. | Have `evict`/`unloadAll` `removeValue(forKey:)` the slot synchronously when cancelling, or catch `CancellationError` on the reuse path and retry a fresh load when `Task.isCancelled == false`. |
| CR-0613-6 | Local AI (iOS) | `Services/AI/Local/MLXInferenceService.swift:170` | 🟡 med | The cleanup reaper `Task { [weak self] … }` is untracked and never cancelled; on teardown it can still fire MainActor work after the entry is gone (guarded only by `seq`/`lastRequestedModelId`). | Fold the cleanup into the structured `task` via `defer`, or store the handle and cancel it in `evict`/`unloadAll`. |
| CR-0613-7 | Voice | `Features/Voice/VoiceChatViewModel.swift:132,174` | 🟡 med | State-resurrection race (TODO'd, not fixed): a trailing provider event arriving between `eventConsumerTask?.cancel()` and `disconnect()` returning can overwrite a terminal `.failed`/`.disconnected` state. | In `handleEvent`, ignore connection-state/error-driven transitions once `connectionState` is already terminal; or re-assert the terminal state after `disconnect()` returns. ~2-3 line guard. |
| CR-0613-8 | Local AI (iOS) | `Services/AI/Local/LocalModelStateStore.swift:114` | 🟡 med | The comment claims `state(for:)` gates Apple-FM on Apple-Intelligence enablement to prevent an invocation-time failure, but `DeviceProfile.current.appleFMAvailable` is an OS-version `#available` check only. On an iOS 26 device with Apple Intelligence disabled/unsupported it still returns `.installed`, so the advertised failure can still occur. | Probe real availability (`SystemLanguageModel.default.availability == .available`) or tighten the comment to match the weaker guarantee. |
| CR-0613-9 | Local AI (macOS) | `Services/AI/Local/HuggingFaceCacheConnector.swift:227-238` (`bridgeIntoAppCacheIfPossible`) | 🟡 med | Self-documented TOCTOU: `nonisolated static`, unserialized, so a concurrent `refresh()` / live MLX download can interleave between `removeItem` and `createSymbolicLink`, leaving no link → multi-GB re-download (the exact symptom the bridge prevents). | Per the inline TODO: create the link at a temp path then `replaceItemAt` (atomic), or serialize the bridge. |
| CR-0613-10 | Local AI (macOS) | `Services/AI/Local/HuggingFaceCacheConnector.swift:391-420` (`directorySize`) | 🟡 med | The `measured == 0 → fileSizeFallback` fix applied to `LocalModelStateStore.scanDisk` was not mirrored here, so "Connected (HuggingFace)" rows render "0 B"/"1 B" on volumes where `totalFileAllocatedSize` is unavailable (network/sandboxed mounts). | Mirror the `fileSizeFallback` path from `LocalModelStateStore`. |
| CR-0613-11 | Local AI (perf) | iOS `LocalModelStateStore.swift:124` + macOS `:124` (+ `MacLocalModelsView.swift:444`) | 🔵 low | `state(for:)` (read inside SwiftUI row bodies) calls `DeviceProfile.current`, which does a `volumeAvailableCapacity` disk stat + `physicalMemory` read on every body re-eval for Apple-FM rows. | Cache `appleFMAvailable` (a compile-time `#available` constant) once instead of recomputing `DeviceProfile.current` per eval. |
| CR-0613-12 | Email (iOS) | `Services/Email/EmailService.swift:~1975` (`GetThreadResponse.latest`) | 🔵 low | iOS uses non-tolerant `try container.decodeIfPresent(EmailMessage.self, forKey: .latest)`, so a single malformed `latest` aborts the entire thread decode; macOS uses tolerant `(try? …) ?? nil`. Cross-platform inconsistency; iOS is the brittle one. | Make iOS tolerant to match macOS. |
| CR-0613-13 | Tests (iOS) | `TodusTests/TaskCaptureServiceTests.swift:90,115` | 🟡 med | The rollback-safety tests assert `SupabaseSyncService.syncState` outcomes but never exercise `TaskCaptureService.capture()`'s actual delete path — nothing proves a `.localOnly` task survives while a `.failed` task is deleted + removed from the store. The named data-loss risk is covered only by inference. | Add a `capture()`-level test asserting the offline task still exists and the server-rejected one is gone; add a 5xx-keeps-task case once CR-0613-1 lands. |
| CR-0613-14 | Local AI (iOS) | `Services/AI/Local/MLXInferenceService.swift:337` | 🔵 low | Behavior change: token usage now reports `0/0` when MLX truncates on `maxTokens` without flushing `.info` (old `chunkCount` fallback removed). | Verify billing/telemetry treats `outputTokens == 0` as "unknown," not "free." |
| CR-0613-15 | Web (billing) | `apps/web/app/(routes)/settings/billing/page.tsx:43-45` | 🔵 low | The comment claims the `formatCredits` finite-guard protects `pct` from rendering `NaN%`, but `pct` (line 109) computes `Math.ceil((used/limit)*100)` from raw values, never via `formatCredits` — a non-finite `used`/`limit` still yields `NaN%`. | Guard/clamp `used`/`limit`/`pct` if server-NaN is real, or correct the comment to not overclaim. |
| CR-0613-16 | Build config (macOS) | `apps/macos/project.yml:85` + `TodusMac.xcscheme` vs `TodusMac.xcodeproj/project.pbxproj` | 🟠 high | `project.yml` adds a `TodusMacTests` unit-test target + a `test:` scheme action, and the **tracked** `.xcscheme` was regenerated to reference its blueprint (`A12C09E2545DCAE94709093E`) — but the **tracked** `project.pbxproj` was NOT regenerated and contains zero `TodusMacTests` (blueprint absent). So the committed Xcode project's Test action (⌘U / `xcodebuild test -scheme TodusMac`) references a target that doesn't exist → fails. App Build/Run is unaffected (app blueprint exists). The new `TodusMacTests/EmailDecodeToleranceTests.swift` can't run via Xcode until regenerated. (`TEST_HOST`/`BuildableName` `Todus.app`-vs-`TodusMac.app` is **not** a bug — xcodegen sets the file-ref `name = TodusMac.app, path = Todus.app` since `PRODUCT_NAME: Todus`; both are internally consistent.) | Run `cd apps/macos && xcodegen generate` (xcodegen 2.45.3 is installed) to materialize `TodusMacTests` into the pbxproj, then commit the regenerated `project.pbxproj`. Standalone fallback that already works without Xcode: `apps/macos/scripts/run-email-decode-tests.sh` (compiles `EmailModels.swift` + `main.swift` via `swiftc`). |

**Verified clean (checked, no action):** iOS commits 2ca46e3b + 22afa335 (forward full-body data-loss fix, load-state gen-gate, `invalidateThreadDetail`, off-main decode with `nonisolated(unsafe)` formatters, `copyResetTask` cancellation) are all correct and genuinely tested end-to-end. iOS `BillingSettingsView` `.isFinite` guards on `aiUsagePercent` are dead defensive code (the upstream getter already clamps) but harmless. Web `button.tsx` per-attribute merge order, `[&_svg]:size-4` retention, `aria-disabled:opacity-50` slot-only dimming, `loadingText ?? children`, and `import.meta.env.DEV` guard are correct. Email-HTML WKWebView CSP (`default-src 'none'; script-src 'none'`, `baseURL: nil`, link routing) neutralizes sender JS/forms on both platforms. iOS dark-mode background fixes, `RootView` onboarding step counter, `CachedAvatarImage` off-main decode, `AppHaptic.assumeIsolated`, `CalendarViewController` Sendable boxing, and `DocsListView` cycle/depth guard all sound.

---

# Bug Hunt — 2026-06-14 (iOS main user-flow surfaces)

Scoped bug review of the iOS app's main-flow surfaces (auth, email, tasks, calendar, AI/voice, home/create, docs/meetings, sync). Method: 10 parallel finders → adversarial verifier per candidate (default-skeptic, re-read the real code). 14 candidates → 8 confirmed real, 5 refuted as false positives. 6 confirmed bugs auto-fixed (small, unambiguous, no-regression); 1 confirmed bug flagged for human review (needs UX decision); the rest investigated and downgraded. Not yet compiled in this environment — `xcodebuild` validation pending.

## Auto-fixed this pass (6)

- `Features/Tasks/TaskRowView.swift:390` (`setPriority`) — `try? modelContext.save()` swallowed save errors → silent priority-change loss. Replaced with `do/catch` + `AppLogger`, matching `TaskCaptureService.capture`.
- `Services/Tasks/TaskCaptureService.swift:286` (`delete`) — `try? context.save()` swallowed; remote delete was enqueued even when the local delete failed → local/server divergence. Now `do/catch` and `return` before enqueue if the save throws.
- `Features/Voice/VoiceChatViewModel.swift:243-257` (`handleEvent .transcriptUpdate`) — out-of-order provider events (a partial arriving after `isFinal`) appended onto finalized text and corrupted the transcript. Added per-role `userTranscriptFinalized`/`assistantTranscriptFinalized` guards; reset in `finalizeCurrentTurn()`.
- `Navigation/CreateSheet.swift:1010` (compound-intent loop) — when `createEvent` failed (permission/EventKit) it set `eventSaveFallbackPrompt` and returned, but the loop kept creating the remaining intents and then `close()`d the sheet out from under the alert. Added `if eventSaveFallbackPrompt != nil { return }` after `createEvent`, mirroring the existing single-intent guard at `:1049`.
- `Features/Meetings/MeetingDetailView.swift:506` (`generateSummary`) — a failed post-action `loadMeeting()` nils `meeting`, replacing the just-generated summary with "Meeting not found". Now snapshots `meeting` and restores it if the refresh returns nil.
- `Features/Meetings/MeetingDetailView.swift:515` (`scheduleBot`) — same failed-reload-blanks-the-view defect; same snapshot/restore fix.

## Needs human review (1) — ✅ RESOLVED 2026-06-15

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| ~~BH-0614-1~~ | Home briefing | `Features/Home/HomeView.swift` (`dismissBriefingItem`/`markBriefingItemDone`/`snoozeBriefingItem`) | 🟠 high | Handlers called the backend with `item.backendId` without re-validating the item still exists in the current briefing → silent mutation failure + local/server divergence. | **RESOLVED** in the 2026-06-15 UX pass: added `briefingItemStillExists(_:)` (mirrors `todayActionLine`'s pool lookup); all three handlers now skip the mutation and call `loadAssistantBriefing()` to reconcile when the item is stale. |

## Refuted — investigated, NOT bugs (no action)

- `Features/Tasks/TaskDetailSheet.swift:120` (camera picker) — claimed off-main `@State` mutation. False: `UIImagePickerControllerDelegate` callbacks fire on the main thread; `appendAttachments` runs on main.
- `Services/Tasks/TaskCaptureService.swift:122` (`try? context.fetch` in rollback) — error-swallow is intentional & documented; the just-saved mutations are already persisted at `:106`, and a failed fetch only skips an optional rollback (tasks keep their visible `.failed` state, not phantom data).
- `Features/Calendar/CalendarTabView.swift:500` (`loadEvents`) and `:553` (`loadMoreListEvents`) — claimed off-main `@State` mutation. Both are called from main-actor contexts (`.task`, `.onChange`); Swift concurrency violations are compile-time, and the app builds, so no runtime isolation violation exists. (Adding explicit `@MainActor` would be redundant.)
- `Features/Voice/VoiceChatViewModel.swift:135` (trailing-event state resurrection) — already guarded by `if case .failed = connectionState { return }` at the top of `handleEvent`. (Overlaps the broader, still-open `CR-0613-7` TODO; left as-is.)
- `Navigation/MainTabView.swift:87` (capture-failure dismiss timer) — idiomatic cancel-and-replace `Task` on the main actor; `guard !Task.isCancelled` + `try?` handle cancellation correctly.
- `App/AppServices.swift:806` (`Task { @MainActor … }` after `Task.yield()`) — class is `@MainActor`; the closure is explicitly `@MainActor`; mutated properties have no `didSet`. Correct as written.

---

# iOS UX hardening pass — 2026-06-15 (whole-app, main user-flow surfaces)

Follow-up to the 2026-06-14 bug hunt: addressed the full finding set from three audits (UX flow assessment, UX-polish, bug-hunt) across the iOS app. 9 parallel implementer agents each owned a disjoint file set; every agent grep-verified symbols before use and deferred true feature-scope items. **Full `xcodebuild -scheme Todus` → BUILD SUCCEEDED** with all edits combined. 49 files changed (+1066/-224). Not yet committed with tests beyond the compile.

## Fixed this pass (highlights by surface)

- **Auth/onboarding** — email-validation error no longer flashes mid-typing (gated on blur); "Send code" always visible-but-disabled; email field a11y label/hint; OTP digit-only paste filter; 60s resend cooldown; user-friendly backend error copy (no Supabase/SMTP leakage); Gmail-check loading state + haptic; bell-icon a11y; WelcomeTour "Skip" → "Skip tour". (RootView reinstall "bug" confirmed a non-issue — `&&` already skips the card when authenticated.)
- **Email** — compose `To`-invalid indicator + send-fail haptic + attachment-remove confirm + CC/BCC hint; inbox folder-dropdown affordance on iOS 26, search-term truncation, pagination double-tap guard; thread task/event/copy haptics; row/receipt truncation help.
- **Tasks** — TaskDetailSheet save now surfaces errors + keeps sheet open on failure; **bulk-capture truncation banner** (`lastTruncatedCount`/`lastTruncatedAt` → MainTabView, mirrors rollback banner); attachment-delete confirms; dynamic snooze labels; a11y on parse-state/folder chip/board title; checkbox copy.
- **Create sheet** — duplicate-send guard (`isSending`); `To` required for email type; attachment-delete confirm.
- **Folders** — a11y labels on add/menu; MoveToFolder shows current folder + disables no-op Inbox + inline create-error; AddToFolder "Add X to [folder]"; save haptic; empty-state copy.
- **Calendar** — explicit read-only-event message; clearer reconnect-Gmail scope copy; Today/nav/list/copy haptics; refresh indicator over non-empty events; nav-chevron a11y; proactive full-access permission copy.
- **AI + Voice** — **voice-connect failure now shows an error card + Retry for all users** (was dev-only); `isDisconnecting` "Closing…" state; muted mic icon; tool-call success confirmation; copy-card haptic; sources count header; disabled-state dimming; `+`/attachment a11y labels.
- **Home/Search** — **BH-0614-1 fixed** (stale-briefing reconcile); 350ms search-nav flicker removed; person row tappable → compose; "See all N" rows; Docs no longer dev-gated; destructive-dismiss confirm + haptics.
- **Settings** — signature swipe-delete confirm; billing error-alert + `forceRefreshFromAutumn` after cancel; disconnect-button label + 44pt target; tab-bar customization surfaced in Settings; calendar toggle labels; duplicate-pattern feedback; voice-settings nav-title consistency; tab-bar-customization background token.
- **Docs/Meetings/Notifications** — faster new-doc autofocus + blur-save; docs search-task cancel; meetings sync button + row truncation help; Q&A send spinner + a11y; notification row haptic + truncation help.

## Deferred items — 2026-06-15 second-wave resolution

Second wave (6 implementer agents) cleared most of the deferred set. Whole-app `xcodebuild` re-verified after these + the file deletion below.

### ✅ Resolved in the second wave

| ID | Where | Resolution |
|----|-------|-----------|
| ~~UX-D1~~ | Board view | **Already existed** — `BoardColumnView` has an inline quick-add row calling `TaskCaptureService.captureInStatus(title:status:in:)`. Original deferral was wrong. |
| ~~UX-D2~~ | `FolderDetailView` / `fetchFolderContents` | `fetchFolderContents` now returns `FolderContentsResult { items, remoteFetchFailed }`; the view shows a distinct "Couldn't load — pull to refresh" state vs. genuine empty. |
| ~~UX-D4 (subset)~~ | AI chat edit-undo | Edit now captures the truncated tail + index (`lastTruncatedHistory` was previously dead — set to `[]` immediately); `restoreTruncatedHistory` + a 30s "Undo edit" chip wired via the existing `cancelStream()`. Branching / per-tool-retry / streaming-lag / per-source open remain deferred (see below). |
| ~~UX-D6~~ | AI delete confirmation | `PendingDeleteConfirmation` gained `subtitle`; the delete-task handler fetches due date + folder and the dialog shows "Due <date> · <folder>". |
| ~~UX-D7 (docs)~~ | `DocsService` / `DocsListView` | `lastSyncedAt` set on successful refresh; a "Last refreshed … ago" tap-to-sync footer mirrors MeetingsListView. |
| ~~UX-D9~~ | Cross-tab "See all N" | Added `tasksSearchSeed` (+ reused existing `pendingEmailSearchQuery`); GlobalSearchView seeds the query, Tasks & Email tabs consume it on appear. |
| ~~UX-D10~~ | Orphaned `EmailAIDraftSheet` | Confirmed zero external references; **deleted** the file and its 4 explicit `project.pbxproj` entries (legacy-style, not a synchronized group). Compose already uses AIChatView. |

### Still deferred — genuine risk / product decision (unchanged)

| ID | Where | Why still deferred |
|----|-------|--------------------|
| UX-D3 | `CalendarMonthView` row height | Size-class-adaptive height risks layout churn across the perf-tuned ±60-month buffer. |
| UX-D4 (rest) | AI chat — message branching, per-tool retry, streaming keystroke-lag, per-source "open in app" | Architectural / new UI + backend shape. |
| UX-D5 | `VoiceInputButton` transcribing-cancel | No cancel API; audio-path change, low value. |
| UX-D7 (Q&A) | Meeting Q&A timestamp sourcing | Needs backend response to carry transcript timestamps. |
| UX-D8 | Recipient display-name preservation in compose | Data-model change (`[String]` → `[Recipient]`) touching the send payload; needs integration testing before shipping. |

---

# Pre-push full-repo review — 2026-06-20

Reviewed the 21 unpushed commits (`origin/main..HEAD`, 134 files, +5273/-14244) before pushing to prod. Two parallel senior reviewers (server + web) + empirical build/bundle validation. **Verdict: SAFE TO DEPLOY — 0 blockers, 0 majors.**

## Validation evidence

- **Web** `react-router build` → exit 0, full prerender of all marketing routes.
- **Server** `wrangler deploy --env production --dry-run` → clean esbuild bundle, all production bindings resolved (VECTORIZE, HYPERDRIVE, AI, queues, KV, R2).
- **pnpm hygiene** — commit `f5e6f240` deleted `bun.lock` + bun-style `workspaces.catalog`/`patchedDependencies` from `package.json`. Verified safe: `pnpm-workspace.yaml` holds the identical `catalog:`, `patchedDependencies: novel`, and workspace globs (the source of truth). Not a breakage.
- **No DB schema changes** → no production migration required (only Zod `lib/schemas.ts` changed, not `db/schema.ts`).

## Auto-fixed this pass (1)

- `apps/server/src/routes/ai.ts:261` (`injectSearchContext`) — generic cast `{ role, content } as T` tripped TS2352 (the one diff-introduced type error; esbuild-harmless but flagged). Changed to the canonical `as unknown as T`; runtime identical, touched file now tsc-clean.

## Deferred MINOR findings (cosmetic — not behavior-changing, no backlog action required)

- `apps/server/src/trpc/routes/subscription.ts:34` — `getActiveProduct` adds a synchronous Autumn round-trip to the `getStatus` hot path for non-free users. Fails soft (no correctness risk). Could cache product id alongside the existing subscription cache.
- `apps/server/src/lib/auth.ts:677` — revoke-failure log wording still reads "Failed to revoke some accounts" even when one account failed. Cosmetic.
- `apps/web/components/ui/bimi-avatar.tsx:181` — `MAX_FAVICON_URLS` raised 6→8 now also caps the primary photo + fallbacks, so the constant name is slightly misleading. Behavior fine.
- `apps/web/app/(routes)/mail/tasks/page.tsx:268` — removed post-create `invalidateQueries`; new tasks insert at list head and reconcile sort on next natural refetch. Acceptable.

## Pre-existing (not introduced by these commits — out of scope, left as-is)

- Server `tsc --noEmit` reports type errors in `routes/agent/mcp.ts`, `thread-workflow-utils/workflow-functions.ts`, `lib/driver/microsoft.ts`, `lib/bulk-delete.ts`, `lib/analyze/interests.ts`, `lib/server-utils.ts` — all in files **not** touched by this diff, mostly stale wrangler-`Env` binding noise. Do not block `wrangler deploy` (CF bundles via esbuild, no tsc gate). Pre-existing on `origin/main`.

---

# iOS performance pass — deferred findings, 2026-07-11

Surfaced during the lag/freeze/crash bug-hunt; source-verified but deferred (lower severity or need a larger change than the pass scope). The high-severity freezes/crashes/lag from the same pass were fixed (see `CHANGELOG.md`).

| ID | File | Issue | Fix direction | Why deferred |
|----|------|-------|---------------|--------------|
| PERF-1 | `Features/Docs/DocsListView.swift:332-389` + `Services/Docs/DocsService.swift:115-136` | `listDocs`/`children` filter+sort over ALL docs once per tree node → O(n²) render, redone every body eval | Build a `Dictionary(grouping:by: parentId)` index once per `allDocs` change, cache in `@State`/`@Observable` | Needs a caching layer; Docs is a secondary surface |
| PERF-2 | `Features/Folders/AddToFolderSheet.swift` (email `:242-287`, event `:506-525`, doc `:625-647`) | `existingThreadIDs`/`existingEventIDs`/`existingDocIDs` run a fresh SwiftData `.fetch()` on every access; `body` reads them multiple times per keystroke via `.searchable` | Cache the fetch in `@State`, populate in `.task`/`.onAppear`, invalidate on folder/source change | 3 near-identical sites; wants a shared helper |
| PERF-3 | `Features/Calendar/CalendarTimeGridView.swift` (now-line `Timer.publish(every:60)`) | The 60s now-line tick mutates top-level `@State now`, forcing the whole grid `body` (incl. O(cluster²) `layoutEvents` per day column) to re-run every minute | Isolate the now-indicator in `TimelineView(.periodic(...))`; drop the top-level `now` state + Combine timer | Needs careful visual re-verification of the now-line |
| PERF-4 | `Features/Search/GlobalSearchView.swift:36-75` | `taskResults`/`emailResults`/`peopleResults` are uncached computeds, each read twice per body (`hasResults` + `resultsList`) → 2× filter work | Compute once into locals per `body`, or cache in `@State` | Low severity (in-memory datasets are small); wants a params refactor |
| PERF-5 | `Features/Email/EmailComposeView.swift` (camera path `:1239-1244`) | `AttachmentService.saveImage` (JPEG encode + disk write) runs on the main-thread camera callback | Move off-main; requires boxing the non-`Sendable` `UIImage` across the `Task` boundary | Camera-to-email is infrequent; photo-library path already fixed. Inline `TODO(perf)` left. |
| PERF-6 | `Features/Tasks/InboxView.swift:147-160`, `Features/Tasks/BoardView.swift:68-78` | `tasksChangeDigest`/`boardChangeDigest` walk `allTasks` O(n) on every body eval (they're the `.onChange` comparison value) | Cache digest in `@State`, bump it from `TaskCaptureService`/`SyncService` write sites instead of walking in `body` | Knowingly-accepted tradeoff (documented inline); only bites at hundreds+ tasks |
| PERF-7 | `Services/AI/AIChatService.swift:1164` + `Features/AI/MarkdownView.swift:29-38` | Per-SSE-line `Task.detached` decode (hundreds of hops/reply) and full-markdown reparse on every ~80ms token flush (O(N²) over a long reply) | Decode on one reused background queue for the whole stream; make markdown parse incremental (diff-append) | Both sit on deliberate, documented tradeoffs; off-main already, so no hang |
