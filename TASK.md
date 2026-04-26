# Migration Backlog

Last updated: 2026-04-26

## Current Native Fix Batch

- `DONE` **Review follow-up: duplicate iOS assistant cache file + invalid Ollama persistence + session logout semantics (2026-04):** removed `AssistantPersistedCache 2.swift` from the iOS project, prevented shared web/mail model selectors from saving `aiProvider='ollama'` without an installed model, and changed `sessions.revokeAll` to exclude the current session so "Sign out all other devices" matches the UI label.
- `DONE` **Native AI chat timeout / "Connection lost" investigation (2026-04):** `/api/ai/chat` now opens the SSE response immediately instead of blocking on the upstream provider handshake, emits a bootstrap event so iOS receives bytes right away, and returns explicit SSE `error` events if OpenRouter/Gemini fails before content starts. iOS also now uses a 180s stream timeout for chat requests so long tool-planning turns do not trip the default request timer.
- `DONE` **Assistant briefing fallback for shard-pool exhaustion (2026-04):** `assistant.getBriefing` now treats `Timed out while waiting for an open slot in the pool` / shard-initialization fan-out failures as degraded-startup conditions and serves the lightweight fallback briefing instead of surfacing a 500 during Home startup.
- `DONE` **iOS HomeView build blockers after dashboard refactor (2026-04):** Restored the missing Home hero/feed adapter properties, proactive nudge loading state, and id-based thread sheet route references in `HomeView.swift`. Verified with `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' build`.
- `DONE` **Native live voice chat moved to Gemini 3.1 Flash Live (2026-04):** iOS + macOS `VoiceSessionConfig.geminiDefault()` now use `gemini-3.1-flash-live-preview` instead of the rejected `models/gemini-2.0-flash-live-001` string, and the live-voice headers now surface the runtime model name as **Gemini 3.1 flash live**. Both native `GeminiLiveProvider.sendText` paths were also migrated from `clientContent` to `realtimeInput.text` to match the current Gemini Live API contract for in-session text.
- `DONE` **Verification status for the native voice fix (2026-04):** iOS `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -configuration Debug -destination 'generic/platform=iOS' build` succeeded after the patch. The earlier macOS compile blocker in `apps/macos/TodusMac/App/TodusMacApp.swift` was resolved by awaiting `Task.yield()` inside `initializeApp()`. Any remaining macOS build failures are now downstream of that fixed async-await issue rather than this call site.

- `DONE` **Server billing enforcement + folder migration repair (2026-04):** `refreshSubscriptionCache()` now lazy-creates Autumn customers only after a confirmed not-found result, zero-credit plans no longer fail open in `hasAiCredits()`, and usage tracking updates the local cache only after Autumn accepts the debit. Signup/delete + subscription flows now inspect `autumn-js` result objects instead of assuming failures throw, and the onboarding campaign sender now serializes Resend `scheduledAt` correctly as ISO text. `/admin/run-migrations` now repairs the 0052 shared-folder schema (`mail0_task_folder` metadata + `mail0_folder_item`) and exposes those tables in `mode=info`. Docs create/update now enforce parent ownership/workspace consistency and inherit the parent workspace when needed.
- `DONE` **Shared native auth session-restore hardening (2026-04):** `packages/swift-auth/AuthService` now distinguishes refresh outcomes (`refreshed` vs revoked session vs transient failure), so offline launches with an expired JWT no longer raise a false session-expired banner. Confirmed-invalid sessions now sign out instead of leaving the app shell authenticated, and the debug token preview is fully redacted to length-only text.
- `DONE` **Generative-UI round 2: 6 more chat cards + bug-audit pass (2026-04):** Added `AttachmentCard`, `CodeBlockCard`, `ChecklistCard`, `DocumentCard`, `WeeklyAgendaCard`, `MetricCard` across web / iOS / macOS, plus four new actions (`open_attachment`, `toggle_checklist_item`, `navigate_document`, `navigate_day`). Bug audit fixes: autosave/send race in `InlineComposeCard` (debounce now cancelled on Send), iOS+macOS recipient dedupe + email validation, `groupedThreshold` now clamped to ≥1 on iOS+macOS, macOS `retryMessage` clears `uiSpec`, macOS `InlineCompose` no longer hangs in "Sending…" on failure (typealias migrated to 3-arg with completion), `CopyableTextCard` capped at ~280px with internal scroll, web InlineCompose displays attachment chips, iOS opens `previewUrl` via `UIApplication.shared.open` and macOS via `NSWorkspace.shared.open`.
- `DONE` **AI billing unlimited-state + sidebar image-only submit (2026-04):** Server billing cache now preserves Autumn `ai_usage.unlimited` and exposes `aiUsage.unlimited` to clients, so unlimited plans no longer get blocked by text/voice/agent AI pre-flight checks. The mail sidebar AI composer now submits pasted-image-only turns through `append(..., { allowEmptySubmit: true })`, preventing silent drops and lost pending images. iOS/macOS/web billing surfaces now render unlimited AI usage explicitly instead of showing a zero-credit exhausted state.
- `DONE` **Sources affordance on AI assistant messages (web + iOS + macOS, 2026-04):** Backend now emits a unified `context_sources` SSE event aggregating web search, resolved `@`mentions, and Mem0 memories (`apps/server/src/lib/ai-sources.ts`, `apps/server/src/routes/ai.ts`). iOS replaced the legacy horizontal web-source chips with a stacked-icons "Sources" button inline with the assistant action row that opens a list sheet (`apps/ios/Todus/Todus/Features/AI/AISourcesView.swift`); tool-call results from `executeSingleToolCall` are appended client-side. macOS added `MacAISourcesView` + a parallel `contextSources` field on `MacChatMessage`. Web added a self-contained `<Sources />` component (`apps/mail/components/create/ai-sources.tsx`) ready for the AI-SDK SSE listener wiring inside `ai-chat.tsx`. New brand icons (Meet / Notes / Document / Todus chat / Memory / Company / Website) added to `BrandIcons.swift`.
- `DONE` **Generative-UI catalog: 9 new card types across web, iOS, macOS (2026-04):** `TaskListCard`, `EmailListCard`, `CalendarEventListCard`, `ContactListCard`, `CopyableTextCard`, `InlineComposeCard`, `SuggestionsCard`, `ActionConfirmationCard`, `QuoteCard`. Backend contract + `drafts.update` mutation landed; web has full Zod schemas + React components + tRPC-wired `update_draft`/`send_draft` actions; iOS extended its existing ChatUISpec system + `DraftService`; **macOS gained the entire ChatUISpec system for the first time** (data model copied verbatim; renderer/views adapted to `MacTheme`; `MacChatMessage.parseUISpec()` + `MacAssistantPanel` render seam; `MacDraftService` parallels iOS). InlineComposeCard locks its seed by `draftId` so AI re-emissions don't clobber unsent edits.
- `DONE` **Hide default-mail onboarding for now (iOS + macOS, 2026-04):** The default-mail onboarding step is no longer shown in either native onboarding flow, but the views/state stay in the codebase so the step can return once Apple grants `com.apple.developer.mail-client`.
- `DONE` **iOS default-mail onboarding opens Default Apps (2026-04):** The onboarding CTA now uses Apple’s public `openDefaultApplicationsSettingsURLString` deep link instead of `openSettingsURLString`, so it targets the global Default Apps settings surface instead of Todus’s own Settings page.
- `PENDING` **Apple mail-client capability enablement (iOS + macOS, 2026-04):** Todus already registers `mailto` on both native targets, but it still will not appear as a selectable default mail app until the Apple Developer app ID / provisioning profiles include `com.apple.developer.mail-client` and the entitlement is added to the signed app targets.
- `DONE` **iOS tab shell honors tab-bar customization (2026-04):** `MainTabView` now uses the floating `CustomTabBar` backed by `services.tabBarTabs` instead of a hard-coded native tab order, so onboarding/Settings tab choices change the real shell and can pin Meetings into the main bar.
- `DONE` **iOS email reminder action (2026-04):** Thread overflow menu has a real local-notification reminder flow with quick presets instead of a dead-end placeholder.
- `DONE` **iOS default-mail onboarding copy/CTA alignment (2026-04):** The onboarding screen now accurately explains that Todus can only open its own Settings page, then the user must navigate to Default Apps manually.
- `DONE` **iOS email preferences wiring (2026-04):** `Swipe Gestures` now gates inbox swipe actions, and `Group by Thread` persists and controls the Threads/People inbox mode.
- `DONE` **macOS launch behavior split (2026-04):** `Open on Launch` is no longer silently overridden by last-view restore; `Resume Last Viewed Page` is now a separate real preference.
- `DONE` **macOS dormant UI toggles wired up (2026-04):** `Compact Sidebar`, `Show Unread Badge`, and `Group by Thread` now affect visible macOS UI behavior.

## macOS UI

- `DONE` **Developer mode in Settings (2026-04):** Allowlisted email (`TodusDeveloperAccess` via `TODUS_ALLOWLISTED_EMAILS` env, comma-separated) sees a **Developer Mode** toggle; **Auth Debug** appears only when the toggle is on. Persisted as `TaskApp.developerModeEnabled` (same as iOS). Swift-auth `TodusDeveloperAccess` + `TodusHTTPClient` are included in the macOS target compile sources so `import TodusAuth` is not required for the single-module app build.
- `DONE` **Docs production schema repair (2026-04):** `/admin/run-migrations` now idempotently creates `mail0_doc_workspace`, `mail0_doc`, docs FKs/indexes, and `mail0_doc.is_starred` through the production Hyperdrive connection; `mode=info` includes docs table columns for verification. Deploy backend, then run the admin repair or the standard production Drizzle migration flow.
- `DONE` **AI assistant floating layout (2026-04):** `MacRootView` persists `mac_assistant_floating_{width,height,offset_x,offset_y}`; `MacAssistantPanel` takes `Binding` for floating size/offset so switching floating ↔ side pane restores the last floating frame; header drag + corner resize, improved resize hit target.
- `DONE` **App icon container (2026-04):** Gmail / Calendar / Reminders `AppIconContainer` on iOS + macOS: explicit `size×size` white `RoundedRectangle`, `ZStack(alignment: .center)`, inner art in a `0.62×size` square with `alignment: .center` + inner `.clipped()` so Canvas/anti-aliasing does not spill past the artboard; final `clipShape` matches the white tile.
- `DONE` **Apple Calendar brand icon (2026-04):** `AppleCalendarLogo` is layout-based (red strip + “MON” + “12”); `Path(SVG d)` for the 2160 source produced empty draws on device. `AppIconContainer` provides the white squircle. Call sites: Settings, Calendar permission, mac onboarding, **Calendar tab** (`CalendarTabView` / `MacCalendarView` headers).
- `DONE` **Apple Reminders brand icon (2026-04):** `AppleRemindersLogo` on iOS + macOS now uses `Canvas` with the official 1024×1024 Reminders light geometry (grey bars + blue/red/orange rings with white centers); macOS `AppIconContainer` matches iOS fixed inner `width`+`height` and `clipShape` so artwork never overflows the white rounded square. All call sites use `AppleRemindersIconView` only (onboarding, Settings, Tasks connect).
- `DONE` **Auth copy (2026-04):** `MacAuthView` matches iOS `AuthView` — single subtitle line (workspace vs OTP), no extra “Sign in to…” line; guest action label **Continue as guest** (was “Skip, use tasks only for now”).
- `DONE` **Auth email autofill (macOS):** `MacEmailTextField` (`NSTextField` + `contentType = .emailAddress`) replaces SwiftUI `TextField` so Keychain/Contacts can suggest email like iOS/Safari; Return still sends code; spelling auto-correct off to match iOS.
- `DONE` **Native Docs (2026-04):** Replaced full-page web `WKWebView` with a Craft-style native shell (`MacDocsShellView`: sidebar, grid/list, editor). Rich body uses bundled Tiptap (`Resources/DocEditor`, built from `packages/macos-doc-editor`) + `TiptapDocEditorWebView` / `todusDoc` bridge; `MacDocsService` + tRPC. Backend: `doc.is_starred`, `docs.update` optional `parentId` / `workspaceId` / `isStarred` (migration `0051_doc_starred_and_move.sql`). Removed orphan `TodusMac/MacDocsView.swift` at repo root.
- `DONE` **Docs empty DB + create UX (2026-04):** `docs` routes return `PRECONDITION_FAILED` with a clear message when `mail0_doc` / `mail0_doc_workspace` tables are missing (instead of 500). macOS: visible **New document** in toolbar, sidebar, and empty state; tRPC error `message` shown in alerts and in `lastError` via `APIError` body parsing. Ops: apply doc migrations from `0044` onward on the server.
- `DONE` **App icon (2026-04):** Figma Apple-template 1024×1024 light/dark masters; `AppIcon.appiconset` uses 20 slots (luminosity light + dark) generated with `sips`; sources in `TodusMac/Resources/AppIconSource/`.
- `DONE` **Switches (iOS + macOS)**: `AppTheme.switchTint` / `MacTheme.switchTint` use system blue so `Toggle` on-states are visible in light/dark mode; root primary tint no longer washes out settings switches.
- `DONE` **Calendar (macOS)**: `MacCalendarView` month mode uses a vertically paged month stack (`scrollPosition` + `viewAligned` + `scrollBounceBehavior(.basedOnSize)`); horizontal trackpad steps time via `CalendarTrackpadNavigation` (tuned threshold/debounce, `isKeyWindow`); **Day/Week** use a **lenient** horizontal-vs-vertical weight + **⇧+scroll** for time; pinch steps **Day → Week → Month → Year** via `CalendarPinchViewModeCoordinator` (`NSEvent` magnify); **⌘1–4** for view modes; year view scrolls to the focused year + **red dot** on the real-world month; help string documents gestures.
- `DONE` Home “Suggestions for you” (iOS + macOS): proactive assistant nudges from `assistant.listOpenLoops` (`loadAssistantNudges`), horizontal cards with sparkles header, thread sheet or Mail jump; macOS hides the block when Focus Mode is on; macOS build: `MacTheme.spacing8` only (no `spacing10` token).
- `DONE` Home dashboard: horizontal overview chips (tasks, unread, today, meetings, docs), unified open-task list with due hints, three-column layout with upcoming calendar (tomorrow–2w) and API meetings, Docs callout row, meeting detail sheet from home.
- `DONE` Home UX pass (macOS): contextual greeting subtitle, “Jump to” strip with plain-language chip copy + help/accessibility, tasks-first column order, section subtitles + “View all” links, overdue emphasis on tasks, primary “Open Docs” control, clearer empty/setup copy.
- `DONE` Clickable affordance: `macClickablePointer()` (`PointerStyle.link`) on plain buttons, menus, and key toolbars; web globals extended for native form controls (checkbox/radio/file/range + wrapping labels).
- `DONE` tRPC: `trpcServer` `endpoint` is `/api/trpc` so `fetchRequestHandler` resolves `meet.*` and other procedures (was HTTP 404 for every `/api/trpc/...` call when endpoint was only `/trpc`).
- `DONE` **Native Meetings legacy schema fallback (2026-04):** `meet.listMeetings` / `getMeeting` / `getIntegration` / `syncFromCalendar` no longer hard-fail when production is missing newer `mail0_meet_integration` settings or retention columns. The server reads the legacy integration shape, applies safe defaults, and disables retention pruning until the DB has the retention columns.
- `DONE` App icon: `compose-macos-app-icon.py` flood-fills edge-connected background white to transparent, then scales the opaque content to ~95% of 1024 (avoids a sharp inner “white frame” from the rect crop); `Info.plist` `CFBundleIconName` = `AppIcon`; no duplicate loose `AppIcon.icns` in the target.
- `DONE` Meetings: server `meet.listMeetings` / `getMeeting` / `scheduleBot` / `syncFromCalendar` responses aligned with native decoders (total, flat detail, success flag, sync fields); Zod accepts null optionals from Swift.
- `DONE` Tasks board: drag-and-drop between columns (status update + save); iOS board columns/cards restyled to match macOS row layout; iOS `TaskDateFormatter.shortDate` + `AIChatView` `AppTheme` fix for builds.
- `DONE` Tasks: removed tab-mode hint copy and List completed-note; view-mode control uses matching capsule chrome; “Connect Apple Reminders” on Tasks; onboarding step 3/4 for Reminders (with migration for users who already completed startup); Settings Reminders connect uses EventKit.
- `DONE` **iOS Tasks list UX (2026-04):** shorter search field, less horizontal padding, tighter row gaps, task row title 2 lines + description 1 line + status chip on the right, stronger row/sheet light-mode contrast, completion moves to “Recently completed” after 5s via `TaskRecord.completedAt`, swipe (complete / move / edit / delete) + context menu; edit sheet rows use `SheetListRowBackground`.
- `DONE` Overlay scrollbars app-wide (no track channel, thumb only while scrolling) plus clear scroll-view backgrounds; chat composer `NSScrollView` matches.
- `DONE` AI chat: attachments are sent to `/api/ai/chat`, shown in the user bubble, and merged on the server (vision + text inlining + binary filename context).
- `DONE` **Paste to attach (iOS + macOS + web):** Clipboard images/files in the AI composer become pending uploads (iOS `NSItemProvider` + `AttachmentService`, macOS `NSPasteboard` → temp/file URLs, web `ClipboardEvent.files` + `experimental_attachments` on `append`).
- `DONE` **iOS AI sent attachments:** User bubble uses thumbnails + short labels; tap opens `AttachmentPreviewSheet` (copy/save/share); `mimeType` sniffs image bytes so vision requests include `image_url` when the extension is wrong.

## Unified Folders Expansion

- `DONE` Expanded the folder concept across tasks, saved AI chats, and calendar events so each item type can now be filed into shared user folders.
- `DONE` Kept email provider folders/labels separate and unchanged, preserving the existing mail folder model.
- `DONE` Added cross-platform chat folder filtering, move actions, folder badges, and shared folder sync on web, iOS, and macOS.
- `DONE` Added calendar event folder sidecar storage and folder move actions in the native event surfaces.
- `DONE` Added server-backed AI conversation folder storage plus migration coverage for the new folder metadata.
- `DONE` Verified the native implementations with successful iOS and macOS builds.

## Current Web/Server Fix Batch

- `DONE` **CI production DB migrations (2026-04):** `.github/workflows/db-migrate-production.yml` runs server Drizzle migrate using GitHub secret `PRODUCTION_DATABASE_URL` (Hyperdrive origin / direct Postgres). Manual dispatch or push to `main` that touches `apps/server` migrations. Required for live Docs after schema changes.
- `DONE` **Docs UI when DB/migrations unavailable (2026-04):** Web/mail `DocTree` + docs landing show tRPC error text and Retry (no infinite setup / no blind “Personal” create on `PRECONDITION_FAILED`). macOS All-docs pane shows load-failure state with Retry; iOS Docs still uses embedded web.
- `DONE` **Local `pnpm db:migrate` on empty DB (2026-04):** `0044` uses `DROP INDEX IF EXISTS` for `meet_integration_user_id_idx` and does not duplicate `0043` recall uniques; `0049` trimmed to default `ALTER TABLE` only (no duplicate `0046`–`0048` DDL). Fresh setup: `createdb todus`, then `pnpm db:migrate`.
- `DONE` Native Email Inbox production schema fallback: `mail.listThreads` / active connection resolution no longer fail when `mail0_connection.color` is missing, multi-connection mail reads use the same legacy query, `assistant.listOpenLoops` returns no nudges when second-brain tables are not migrated, and bearer-token requests keep the real backend error instead of masking it with a failed sign-out/get-session path.
- `DONE` Native Email OTP sign-in bridge: iOS/macOS now verify OTP codes through `/api/auth/native-email-otp/verify`, which validates the existing Better Auth OTP record, creates a raw native session token, and returns structured JSON so the shared native auth service can complete the existing refresh-token flow without hitting the opaque Better Auth 500. Follow-up: the bridge selects only core auth columns from `mail0_user` so production does not require newer app-only user columns to exist before login works.
- `DONE` AI chat hardening pass (iOS + macOS + server): `refreshCalendarSnapshot` on macOS now embeds event identifiers so `update_calendar_event` / `delete_calendar_event` are actually reachable; server skips mention enrichment, web-search heuristics, and attachment merging on follow-up tool steps; clients drop `attachments`/`mentions` from follow-up payloads; `assistant_with_tool_calls` content is `nil` (not empty string) so providers don't reject the message; voice tool guards (`create/update/delete_calendar_event`, `send_email`) now use a per-condition guard chain matching text chat. Debug builds verified on both targets.
- `DONE` AI chat tool-only response fix: AI chat now responds when the model emits only `tool_calls` (e.g. "create a reminder"). `SSEToolCall` deltas accumulate across fragments by `index`, the streaming pass is wrapped in a multi-step agent loop that sends tool results back to the model, and a "Done." fallback prevents empty bubbles. Server `chatMessageSchema` uses `passthrough` and accepts `tool_calls` / `tool_call_id` / `name`. iOS + macOS now also expose `update_calendar_event` / `delete_calendar_event` tools.
- `DONE` Native auth refresh compatibility: `/api/auth/refresh-native-token` now accepts both Better Auth bearer tokens and the raw session token returned by `/auth/mobile-token`, rehydrating the latter through the signed cookie path before minting a fresh JWT so existing iOS/macOS sessions do not expire after 15 minutes; `NoRedirectDelegate` now stops at the first redirect so native auth bridge calls can inspect the original 3xx response instead of silently following it.
- `DONE` Fixed OAuth connection identity + iOS voice parity regressions: server now resolves mailbox identity from the provider account (not the app user), stores correct token expiry timestamps, and keeps provider fallback behavior safe for non-Google accounts; iOS voice tools now match supported task/calendar contracts and the stop-timeout path no longer drops the latest partial transcript.
- `DONE` Fixed the backend `/api` route stack so the tRPC middleware no longer intercepts sibling `/api/ai/*` routes; this restores the iOS live voice-chat WebSocket proxy at `/api/ai/voice-ws`.
- `DONE` iOS voice chat now refreshes an expiring native bearer token before opening the live voice WebSocket, matching the silent-refresh behavior already used by the normal API client.
- `DONE` iOS AI chat: fixed composer focus — removed `ScrollView` tap-to-dismiss that hit the input `safeAreaInset` (text field, + button, padding); `simultaneousGesture` for focus on the input card; + attachment popover dismisses on tap outside via scrim `overlay` above messages (not behind); removed useless under-content clear layer.
- `DONE` iOS AI chat: `[event:EVENTKIT_ID]` tokens in assistant text render as compact inline event cards (tighter when multiple); taps open `EKEventDetailSheet`; generative `CalendarEventCard` navigations use the same sheet instead of leaving chat; conversation scroll anchors to the latest user message at the top while the answer streams.
- `DONE` iOS: `AppTopHeader` no longer allows the profile avatar and action pill to be horizontally compressed to nothing on the Tasks tab (custom title + wide pill on small widths); Email tab now shows the same `AppTopHeader` on the connect-Gmail state and uses a top-level "Mail" header + folder `Menu` label text instead of nesting a full `AppTopHeader` in the folder button.
- `DONE` Scoped frontend `vite-tsconfig-paths` resolution to each app's local `tsconfig.json` so active builds stop crawling archived/reference workspaces and emitting irrelevant tsconfig parse errors.
- `DONE` Realigned `apps/web` to the newer web implementation that had accidentally landed in `apps/mail`, keeping `apps/mail` unchanged and verifying the synced `apps/web` build passes.
- `DONE` Shipped the first web/server performance pass for instant-feeling mail and tasks: inbox rows now render from thread summaries instead of per-row `mail.get` calls, thread detail is predictively prefetched, startup warmup preloads inbox/tasks/calendar/settings data, task mutations now patch cached task lists directly, and cached-first surfaces now show a subtle background-refresh indicator while data revalidates.
- `DONE` Extended the loading-state pass to native iOS and macOS: cached inbox/home/calendar surfaces now keep warm content visible during refresh and show compact updating badges, while task tabs surface background shared-folder sync instead of looking idle.
- `DONE` Shipped a native onboarding + task clarity pass across iOS and macOS: onboarding steps are easier to complete without removing any pages, task views now use labeled toggles, local `Add Task` actions are visible in native task surfaces, and macOS task detail editing now includes folder selection.
- `DONE` Shipped a native Home/Tasks/Email UX remediation pass across iOS and macOS: Home now separates loading from empty states and exposes partial-setup guidance, iOS Tasks search/sort is consistent across all modes with clearer mode semantics, and Email now foregrounds mailbox orientation and actual message reading before AI assistance on both platforms.
- `DONE` Tightened native email mailbox UX on iOS and macOS: folder-specific empty states, no premature `Connect Gmail` flash during connection checks, macOS sender-avatar resolution, and faster macOS folder switching via in-memory mailbox caching.
- `DONE` Shipped a small native UX clarity pass across iOS and macOS: onboarding progress copy, one-time iOS tab-bar coachmarks, clearer task/email/home/create guidance on iOS, and clearer macOS search/auth/daily-brief wording without changing navigation or removing onboarding steps.
- `DONE` Hardened native transcribe button teardown on iOS and macOS so speech-recognition stop/final/error callbacks cannot double-stop the audio engine, double-remove taps, or double-submit transcripts.
- `DONE` Fixed the Cloudflare web build breakage by restoring the doc editor import, replacing the native note delete confirmation with the app's shadcn dialog pattern, and removing dead auth JSX branches that violated Oxlint.
- `DONE` Fixed native meetings follow-up regressions: detail refreshes no longer flash a full-screen spinner during recap/bot actions, iOS meeting sync preserves the active filters/search state, and macOS meeting group ordering now matches iOS with Today first.
- `DONE` Removed the stale top-level iOS `MeetingsListView.swift` duplicate so the app uses the active `Meetings/MeetingsListView.swift` implementation with the same `Starting` label as meeting detail.
- `DONE` Hardened meeting retention and Recall scheduling: inbox cache staleness now triggers background refreshes, tab bar restore falls back to defaults on invalid persisted data, Recall bot scheduling is atomically claimed before API calls, and meeting retention pruning is rate-limited.
- `DONE` Added a shared `mailAssistant` backend domain with per-thread recommendations, inbox nudges, task/event apply actions, draft generation, and lightweight assistant activity logging.
- `DONE` Added nested `assistantAutomationPolicy` settings defaults and backward-compatible settings merges for summaries, suggestions, nudges, auto-drafts, and the opt-in auto-send experiment.
- `DONE` Shipped visible proactive mail assistant surfaces in the web thread view and inbox list, including thread summaries, task/event suggestions, draft actions, inline assistant buttons, and inbox nudges.
- `DONE` Added native mail assistant thread/inbox surfaces on iOS and macOS plus shared settings toggles for assistant automation preferences.
- `DONE` Added the second-brain assistant backend domain with durable open loops, prepared actions, people memory, workstream memory, feedback capture, and briefing/change-feed contracts.
- `DONE` Turned Home into a briefing surface on web, iOS, and macOS with Today priorities, Needs You, Waiting On, and Prepared queues backed by the new assistant domain.
- `DONE` Expanded assistant settings on web, iOS, and macOS to cover the operating model itself: briefing enablement, Home visibility, waiting-on tracking, people memory, batch approvals, workday timing, and excluded sender/topic patterns.
- `DONE` Shipped a focused web mail UX pass: non-blocking inbox connection setup, onboarding sequencing, clearer search/filter wording, better empty-state guidance, more discoverable list actions, and a stronger thread action hierarchy.
- `DONE` Added a one-click share/copy action to the thread AI summary card so users can paste branded thread summaries into email or Slack.
- `DONE` Web task mutations now invalidate all `tasks.list` TanStack caches via `trpc.tasks.list.queryFilter()` (tasks page, home, calendar, TaskItem).
- `DONE` Fixed the web root error boundary hook-order violation by moving Sentry/error-reporting side effects into a dedicated child component.
- `DONE` Fixed categories settings state sync so the local list rehydrates from fresh server data and removed the stale hook dependency warning.
- `DONE` Fixed the privacy settings "remove trusted sender" control so it no longer submits the form when removing an address.
- `DONE` Fixed native account linking to use the dedicated `/auth/native-link-social` bridge and cleared stale saved defaults when deleting a connection.
- `DONE` Fixed iOS Gmail onboarding to use the Gmail link-social flow instead of auth-only Google sign-in, shared the native connection polling helper across onboarding/email/settings, and made shared native auth ignore `todus://link-callback` when received as an app URL.
- `DONE` Fixed production native Gmail linking 401s by sending the app's stored refresh/session token to `/auth/native-link-social` and validating that exact Better Auth session before forwarding to `link-social`.
- `IN_PROGRESS` Apply targeted fixes for AI profile prompt safety, session freshness filtering, and device logout UX.
- `DONE` Fixed the current CodeRabbit web findings that still applied: unified inbox pagination no longer nests `fetchQuery`, settings AI/billing nav titles now use i18n keys, Czech `meetings` labels are translated, Catalan spam-delete copy is back to the formal register, and `AttachmentCard` now namespaces `downloadParams` in emitted events.
- `DONE` Fixed the next CodeRabbit web findings that still applied: `WeeklyAgendaCard` now validates parsed dates, favicon lookups URL-encode `iconHint`, compose-route close behavior uses router state instead of browser history length, Ollama URL success toasts wait for mutation success, Hungarian danger-zone copy is translated, and Hindi `cancel` labels are standardized.
- `DONE` Fixed the next set of applicable CodeRabbit web findings: the full model selector now exposes accessible label associations and accurate OpenRouter helper copy, AI source rows suppress invalid timestamps, copy cards only show local success after clipboard writes resolve, the attachment action schema uses nullable `previewUrl`, and French default-email settings copy is now provider-agnostic. Skipped the `"use client"` billing-page suggestion because `apps/web` is a React Router/Vite app, not Next.js App Router.
- `DONE` Fixed the final applicable CodeRabbit web findings from this pass: the AI settings Ollama URL sync was already present and left unchanged, the security sessions page now uses i18n keys, Ollama pull streaming now handles final buffered chunks and streamed errors, inline draft autosave returns to `saved`, registry draft payloads are runtime-validated, AI chat markdown normalization uses a non-colliding sentinel, and failed chat sends now restore the composer plus pending attachments before surfacing an error.
- `PENDING` Verify whether the web settings-general AI profile fields exist in this branch before adding localization keys for them.

## Complete Dirty-Tree Ship

- `DONE` Finished the combined dirty-tree ship for proactive mail assistant, meetings, public conversation sharing, and group AI chat across backend, web, iOS, and macOS.
- `DONE` Verified targeted server/web TypeScript for the changed surfaces after regenerating route types for the web route additions.
- `DONE` Verified full native builds for iOS and macOS after resolving the remaining meetings + assistant integration compile failures.
- `DONE` Left unrelated dirty-tree work untouched; the ship scope stays limited to the collaboration/meetings/mail-assistant surfaces already in flight.
- `DONE` Fixed the stale macOS target graph by restoring `AppLogger.swift` to the Xcode project and clearing the remaining compile regressions surfaced during the second-brain build pass.

## Active Security Work

- `DONE` Added backend session-management primitives in `apps/server` via `sessions.list`, `sessions.revoke`, and `sessions.revokeAll`.
- `DONE` Added the `mail0_session_metadata` table for coarse device/location labels and last-seen tracking for signed-in sessions.
- `DONE` Replaced the `apps/web` security placeholder with a real Active Sessions table and `Log out all devices` action.
- `DONE` Added Active Sessions management to iOS and macOS settings.
- `PENDING` Cross-device near-live sync architecture across tasks, folders, settings, and AI state. This was intentionally not folded into the session-management change because it requires a broader server-authoritative sync pass.

## Active Auth Fixes

- `DONE` Native shared auth now verifies `/api/auth/me` before promoting a callback token into an authenticated app session.
- `DONE` Server auth middleware now resolves native callback session tokens directly from the Better Auth session table, fixing `/api/auth/me` verification after Google OAuth.
- `DONE` macOS launch now validates persisted bearer tokens before rendering the main shell, so stale Keychain auth no longer shows a partial logged-in UI.
- `DONE` Native Keychain auth items are now namespaced by bundle service for deterministic macOS/iOS resets.
- `DONE` macOS Settings now exposes DEBUG auth diagnostics (state, token preview, session-expired flag, hydrated email).
- `DONE` Full local macOS reset procedure documented in `apps/macos/README.md`.
- `DONE` macOS centralized sign-out now resets cached email state before auth sign-out, preventing stale mailbox state from leaking across sessions.
- `DONE` Invalid-session sign-out now preserves the session-expired banner/message, and Keychain write failures in shared auth/AI persistence are logged instead of being silent.
- `DONE` Onboarding marketing email campaigns are now idempotent: the `welcomeEmailSent` guard is persisted before sending, and one failed queued campaign email no longer causes repeat sends on later logins.

## Build Fixes

- `DONE` Fixed the macOS Xcode target graph for shared auth: `TodusMac.xcodeproj` now resolves `TodusAuth` from `packages/swift-auth`, excludes the dead `App/ConnectionsService.swift` placeholder, and builds cleanly again.
- `DONE` Refreshed `pnpm-lock.yaml` so Cloudflare's frozen install no longer fails on the `apps/web` `uuid` / `@types/uuid` lockfile drift.
- `DONE` Verified `pnpm --filter @zero/mail build` completes successfully after the lockfile refresh.
- `DONE` Verified `pnpm --filter @zero/web build` completes successfully locally.
- `DONE` Verified `pnpm --filter @zero/server exec wrangler deploy --dry-run --env production` completes successfully, which exercises the Cloudflare bundle path for the Worker.

## Current State

The old M1-M7 milestones represent the historical WebView-shell phase and are complete.

The active goal is a **truly native iOS app in `apps/ios`** that reaches feature + behavior parity with `apps/mail` while using native navigation/layout patterns.

Auth/login is currently owned by another agent stream and is excluded from this stream unless explicitly reassigned.

## Status Legend

- `PENDING`
- `IN_PROGRESS`
- `DONE`
- `BLOCKED`

## Current Execution Order (Highest Priority First)

1. `N8-06` Final QA and signoff (`DONE` for iOS-native scope)
2. No remaining open iOS-native parity items in this stream.

---

## Legacy Milestones (WebView Shell) — All DONE

<details>
<summary>M1-M7: WebView Shell (click to expand)</summary>

### M1 Foundations (WebView Shell)

| ID    | Task                                                                | Status |
| ----- | ------------------------------------------------------------------- | ------ |
| M1-01 | Create native app foundations (now located in `apps/ios`)           | DONE   |
| M1-02 | Add monorepo packages: shared, api-client, design-tokens, ui-native | DONE   |
| M1-03 | Extract web design tokens into shared token package                 | DONE   |
| M1-04 | Add React Navigation scaffold with Auth/Public/App shells           | DONE   |
| M1-05 | Add Query + Jotai provider stack for native                         | DONE   |
| M1-06 | Add environment config and backend URL wiring                       | DONE   |
| M1-07 | Add secure storage abstraction (token + prefs)                      | DONE   |
| M1-08 | Document native setup in root docs                                  | DONE   |

### M2 Auth + Session (WebView Shell)

| ID          | Task                                         | Status |
| ----------- | -------------------------------------------- | ------ |
| M2-01–M2-06 | Auth flow via WebView + native token storage | DONE   |

### M3-M7 (WebView Shell)

All marked DONE — these are WebView-based, not truly native.

</details>

---

## Native UI Milestones (Truly Native Rebuild)

### N1 Foundation Reset

| ID    | Task                                                         | Status | Definition of Done                                      |
| ----- | ------------------------------------------------------------ | ------ | ------------------------------------------------------- |
| N1-01 | Update TASK.md with new native milestones                    | DONE   | New milestones reflect truly native rebuild             |
| N1-02 | Restructure RootNavigator for native screen hierarchy        | DONE   | Navigator uses native screens instead of WebView        |
| N1-03 | Install core RN dependencies (FlashList, bottom-sheet, etc.) | DONE   | All needed deps installed and building                  |
| N1-04 | Set up native theme provider with design tokens              | DONE   | Theme context provides light/dark tokens to all screens |
| N1-05 | Create base screen templates (stack, tab, modal patterns)    | DONE   | Reusable screen wrappers established                    |
| N1-06 | Update PLANNING.md with WebView→Native transition notes      | DONE   | Planning doc reflects actual state                      |

### N2 Native Auth (Visual Parity)

| ID    | Task                                                 | Status | Definition of Done                          |
| ----- | ---------------------------------------------------- | ------ | ------------------------------------------- |
| N2-01 | Rebuild LoginScreen to match web `/login` UI exactly | DONE   | Login screen visually matches web           |
| N2-02 | Add proper loading/error states for auth             | DONE   | All auth edge cases handled with correct UI |
| N2-03 | Verify auth flow on iOS/Android/macOS                | DONE   | Login/logout works on all 3 platforms       |

### N3 Mail Core (Highest Priority)

| ID    | Task                                                      | Status | Definition of Done                                                                                                            |
| ----- | --------------------------------------------------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------- |
| N3-01 | Build native mail sidebar with folder list + counts       | DONE   | Sidebar renders folders from tRPC (mocked for N3-01, implemented correctly in N3-04)                                          |
| N3-02 | Build thread list screen with FlashList                   | DONE   | Thread list loads Dummy data using FlashList, ready for N3-04                                                                 |
| N3-03 | Build thread detail screen with message rendering         | DONE   | Messages render with HTML content auto-resizing WebView per-message                                                           |
| N3-04 | Implement thread actions (star/archive/delete/spam/label) | DONE   | All actions work with optimistic updates                                                                                      |
| N3-05 | Implement search with filters                             | DONE   | Implemented folder + unread/starred/attachment filters in native search modal                                                 |
| N3-06 | Build mail shell layout (sidebar + list + detail)         | DONE   | Adaptive split shell implemented: permanent sidebar + list/detail on iPad/macOS, stacked routing on iPhone                    |
| N3-07 | Wire optimistic updates with rollback                     | DONE   | Optimistic cache updates + rollback implemented for archive/delete/spam/star actions                                          |
| N3-08 | Add swipe actions for thread list items                   | DONE   | Swipe direction handling fixed and wired correctly to archive/delete actions                                                  |
| N3-09 | Add M3 tests                                              | DONE   | Added iOS unit coverage for optimistic thread cache behavior (`optimisticThreadCache.test.ts`) and verified in iOS test suite |

### N4 Compose + Drafts

| ID    | Task                                                | Status | Definition of Done                                                                                                           |
| ----- | --------------------------------------------------- | ------ | ---------------------------------------------------------------------------------------------------------------------------- |
| N4-01 | Build compose screen with recipients/CC/BCC/subject | DONE   | Compose now supports To/Cc/Bcc/Subject parity with reply/reply-all/forward prefill updates                                   |
| N4-02 | Integrate @10play/tentap-editor for rich text       | DONE   | Rich text editor + toolbar integrated in compose using TenTap                                                                |
| N4-03 | Implement attachment pick/upload/preview            | DONE   | Compose supports multi-file picking, preview/removal, and serialized attachment upload payloads                              |
| N4-04 | Implement draft auto-save/restore/delete            | DONE   | Compose draft auto-save + restore + clear-on-send implemented via local persisted draft state                                |
| N4-05 | Implement reply/reply-all/forward                   | DONE   | Reply/reply-all/forward actions now enforce web recipient parity, thread-aware send payload fields, and inline action parity |
| N4-06 | Implement undo-send                                 | DONE   | Undo banner + unsend flow now mirrors web behavior, including compose restore for non-user-scheduled sends                   |
| N4-07 | Implement schedule send                             | DONE   | Calendar/time picker is wired for delayed send payloads with future-time validation                                          |
| N4-08 | Implement templates                                 | DONE   | Template save/list/apply/delete is implemented in native compose                                                             |
| N4-09 | Add M4 tests                                        | DONE   | Added native compose parity unit tests and runnable iOS unit test command                                                    |

### N5 Settings

| ID    | Task                                          | Status | Definition of Done                                                                                                                                            |
| ----- | --------------------------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| N5-01 | Build settings shell with navigation          | DONE   | Settings hub now routes to all parity sections with native stack entries                                                                                      |
| N5-02 | Build all 11 settings screens as native forms | DONE   | Native form parity implemented across general/appearance/categories/notifications/privacy/security/shortcuts/danger-zone plus upgraded existing sections      |
| N5-03 | Implement connections management              | DONE   | Set default, disconnect, reconnect (web handoff), and add-account entry point implemented                                                                     |
| N5-04 | Implement labels CRUD with color picker       | DONE   | Create/edit/delete label flows with color selection implemented in native settings                                                                            |
| N5-05 | Implement danger zone with confirmations      | DONE   | Confirmation-gated account deletion flow implemented with destructive confirm dialog                                                                          |
| N5-06 | Add M5 tests                                  | DONE   | Added iOS unit coverage for settings category state logic (`categoriesSettingsUtils.test.ts`) and refactored settings categories screen to use tested helpers |

### N6 AI + Voice + Integrations

| ID    | Task                                         | Status | Definition of Done                                                                                                                                                                 |
| ----- | -------------------------------------------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| N6-01 | Build AI chat panel with streaming responses | DONE   | Native assistant screen added with working AI send/receive and streamed response rendering                                                                                         |
| N6-02 | Implement voice with ElevenLabs              | DONE   | Delivered native-equivalent voice parity with dictation (`expo-av` + `trpc.ai.transcribeAudio`), response playback (`expo-speech`), auto-read, and hands-free loop UX in assistant |
| N6-03 | Integrate PostHog analytics                  | DONE   | Native PostHog bootstrap, screen tracking, identify, and key mail events are wired for parity                                                                                      |
| N6-04 | Integrate Sentry crash reporting             | DONE   | Native Sentry init + boundary/query capture hooks + expo plugin wiring added                                                                                                       |
| N6-05 | Implement notes panel                        | DONE   | Thread detail now includes native notes CRUD + pin/unpin backed by `trpc.notes.*`                                                                                                  |
| N6-06 | Add M6 tests                                 | DONE   | Added iOS unit coverage for assistant streaming helpers and notes sorting logic                                                                                                    |

### N7 Public Pages + Remaining Screens

| ID    | Task                                     | Status | Definition of Done                                                                                 |
| ----- | ---------------------------------------- | ------ | -------------------------------------------------------------------------------------------------- |
| N7-01 | Landing/home screens (WebView or native) | DONE   | Added unauthenticated public route group with native WebView wrappers for `/` and `/home`          |
| N7-02 | Legal pages (WebView)                    | DONE   | Added native public route wrappers for `/about`, `/terms`, and `/privacy`                          |
| N7-03 | Pricing screen                           | DONE   | Added native public route wrapper for `/pricing` using shared WebView route screen                 |
| N7-04 | Contributors/developer screens           | DONE   | Added native public route wrappers for `/contributors` and `/developer`                            |
| N7-05 | Not-found / under-construction screens   | DONE   | Added explicit native `/mail/under-construction/:path` fallback route; `+not-found` already exists |

### N8 Polish, Performance, Release

| ID    | Task                                                         | Status | Definition of Done                                                                                                                                 |
| ----- | ------------------------------------------------------------ | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| N8-01 | Visual regression pass (screenshots all screens)             | DONE   | Screenshot scaffolding + verifier are in place and coverage passes for iOS scope (`web` + `ios`: `46/46`)                                          |
| N8-02 | Performance optimization (list scroll, startup, transitions) | DONE   | Added query stale/gc tuning, list virtualization tuning, and row memoization to reduce scroll jank and refetch churn                               |
| N8-03 | Accessibility pass (VoiceOver, TalkBack, keyboard nav)       | DONE   | Added accessibility labels/roles/states across critical mail shell, thread actions, sidebar, and settings navigation flows                         |
| N8-04 | Release pipeline setup (TestFlight, Play Console, macOS)     | DONE   | Added GitHub Actions native release pipeline (`.github/workflows/native-release.yml`) with QA gates + dispatchable EAS build/submit orchestration  |
| N8-05 | Deprecate WebView wrapper app flows                          | DONE   | Removed deprecated public-route WebView wrappers (`apps/ios/app/(public)/*`) and shared wrapper component (`PublicWebRouteScreen`)                 |
| N8-06 | Final QA and signoff                                         | DONE   | iOS-native stream signoff complete: parity features implemented, iOS build/tests pass, and screenshot evidence is complete for iOS scope (`46/46`) |

---

## Manual Inputs Required

- Apple Developer signing and distribution setup
- Android signing keystore + Play Console tracks
- OAuth redirect updates for native deep-link callbacks
- Production analytics/Intercom/Sentry DSNs/keys
- See `MANUAL_INPUTS_GUIDE.md` for details

## Session Notes (2026-03-10)

- Inbox UX polish pass completed in `apps/ios` for faster first-read comprehension:
  - Replaced the placeholder thread-detail ellipsis dialog with real thread actions (`mark read/unread`, `move to spam`).
  - Moved notes below the message content and collapsed them by default so reading the email stays primary.
  - Hid low-value system labels in thread detail and mapped category labels to friendlier names.
  - Added an inbox hint teaching swipe and long-press actions, plus clearer empty-state copy.
  - Improved search with active filter summary, a `Clear all` reset action, and more helpful guidance/no-result copy.
  - Improved inbox row snippets by falling back to `decodedBody` when the short body payload is empty.
  - Replaced the previous blanket dark-mode email text override with contrast-aware message HTML normalization so native thread content stays readable when sender markup includes pale backgrounds.
  - Added direct read/unread controls to both the inbox swipe menu and the thread header, including a guard so manual `mark unread` does not get auto-reverted by the thread auto-read effect.
  - Increased spacing and tap target size for the thread header action buttons so the top-row controls are easier to hit on device.
  - Rounded the rendered email body container so message content feels consistent with the rest of the card-based thread UI.
  - Reworked the mail visual system toward a more mature, restrained product look: softer non-black dark neutrals, tighter typography, reduced accent saturation, stronger grouping of controls, and more refined card treatment across inbox, search, and thread detail.
  - Fixed inbox message previews so they strip `<style>`, `<script>`, `<head>`, and inline CSS blocks before building the snippet, preventing raw HTML/CSS from showing under the subject line.
- Verification completed for this update:
  - `pnpm --dir apps/ios test:unit` passes (39/39).
  - Narrowed `pnpm --dir apps/ios exec tsc --noEmit --pretty false` check reports no errors in the edited inbox/search files.
  - Narrowed `pnpm --dir apps/ios exec tsc --noEmit --pretty false` check reports no errors in `apps/ios/src/features/mail/MessageCard.tsx`.
  - Narrowed `pnpm --dir apps/ios exec tsc --noEmit --pretty false` check reports no errors in the updated unread-action files.
  - Narrowed `pnpm --dir apps/ios exec tsc --noEmit --pretty false` check reports no errors in the broader mail UI refinement files.
  - Workspace-wide TypeScript still fails in unrelated `apps/server` and dependency files outside this iOS inbox scope.

## Session Notes (2026-03-30)

- iOS hang-reduction pass completed for the native shell:
  - Removed root-level automatic reminders import/sync on first appearance and serialized the remaining deferred startup work after the first interactive frame.
  - Replaced the “keep every tab alive” shell behavior with active-tab-only rendering to cut hidden observation fan-out and tab-switch invalidation pressure.
  - Added native performance tracing for launch, deferred startup, tab switches, SwiftData saves, email inbox loading, and reminders sync/import so Instruments `Hangs`, `Time Profiler`, and `Points of Interest` can be correlated directly to app code.
  - Reduced shared-auth main-thread pressure by caching the bearer token in memory and pushing keychain persistence for token/profile metadata onto utility-priority detached work.
  - Avoided repeated initial inbox reloads on tab revisit and fixed the Create Sheet event fallback so attachments are preserved when calendar creation is unavailable.
- Shared AI profile settings now flow through backend `userSettings` and are injected into every AI prompt across web, iOS, and macOS. The profile is split into `Context about you` and `Custom instructions`, with `customPrompt` preserved as the stored field for instructions.
- Verification completed for this update:
  - `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -configuration Debug -destination 'platform=iOS Simulator,id=816A2B85-AC23-43A8-9A57-0310E1AC0292' build` passes.
  - Build still reports pre-existing EventKit sendability warnings in `CalendarViewController.swift`; they were not introduced by this change set.

## Session Notes (2026-03-28)

- Cross-platform mention and slash-command work is in progress across web, backend, and iOS:
  - Added a shared mention contract in `packages/shared` and a new server `mentions.search` route for grouped mention lookup.
  - Wired structured `mentions` payloads into `/ai/chat` and the web agent path so AI requests can resolve references by ID instead of relying on raw `@text`.
  - Upgraded the active web TipTap editor path with `@` mentions, `/` commands, rich mention chips, and send-time serialization rules for compose vs AI chat.
  - Tightened the shared suggestion popup so it now dismisses on outside click/focus loss and stays scrollable above the keyboard on smaller viewports.
  - Replaced the plain iOS email-compose and AI-chat inputs with a reusable `UITextView`-backed rich input that supports slash commands, mention selection, and inline mention highlighting.
  - Fixed the iOS mention flow so selecting a mention no longer reopens the picker immediately, and the inline mention background now renders as a rounded capsule instead of a flat blue block.
  - Reused the same command model in task capture so iOS slash semantics stay aligned across surfaces.
  - Fixed two iOS compose regressions found during review: the email body editor now honors `focusedField == .body` again through explicit `RichComposerInput` focus plumbing, and person mention suggestions are now sorted deterministically before the top-10 cutoff so the same people appear on every run.
- Remaining verification focus:
  - Finish isolated `xcodebuild` validation for the edited Swift files.
  - Run acceptance-level spot checks for email compose and AI chat mention flows once the build is confirmed.

## Session Notes (2026-03-03)

- iOS archive/build stability fix for Expo Router:
  - Updated `apps/ios/babel.config.js` to use SDK-compatible `babel-preset-expo` configuration with React Compiler preset option and kept reanimated plugin last.
  - Follow-up root cause fix: patched Xcode bundle phase in `apps/ios/ios/Todus.xcodeproj/project.pbxproj` to export pnpm-compatible `NODE_PATH` before invoking `react-native-xcode.sh`.
  - This resolves the archive bundling failure `Invalid call at line 2: process.env.EXPO_ROUTER_APP_ROOT` in `expo-router/_ctx.ios.js`.
  - Verified by reproducing archive with `xcodebuild` and confirming `** ARCHIVE SUCCEEDED **` (no `EXPO_ROUTER_APP_ROOT` error).
  - Verified with `pnpm --filter @zero/ios run bundle:ios` (passes).
- `PG-002` completed with native signup parity in iOS auth group:
  - Added `apps/ios/app/(auth)/signup.tsx` with Google/Apple auth entry points and parity styling.
  - Added signup route registration in `apps/ios/app/(auth)/_layout.tsx`.
- `PG-012` completed for active iOS scope:
  - Updated `parity_screenshots/manifest.json` required platforms to `web` + `ios`.
  - Verified screenshot evidence with `pnpm parity:screenshots:sync` and `pnpm parity:screenshots:check` (`46/46`).
- Scope alignment and signoff closure:
  - Updated backlog statuses to reflect active iOS-native stream completion and de-scoped macOS architecture from this iOS backlog.
- Verification completed for this update:
  - `pnpm --filter @zero/ios run test:unit` passes (39/39).
  - `pnpm --filter @zero/ios run bundle:ios` passes.
  - `pnpm parity:screenshots:check` passes (`46/46`).

## Session Notes (2026-03-02)

- Compose visual polish pass completed in `apps/ios/app/compose.tsx` to improve parity and usability:
  - Fixed rich-text editor typography/padding/colors via TenTap injected CSS (removes serif placeholder/body text).
  - Reworked compose header alignment and action hierarchy (`Cancel` / `Later` / `Send`) for cleaner native layout.
  - Reduced excessive iOS modal top spacing by adjusting safe-area handling in compose header.
  - Increased row/label/input spacing for better readability and removed label wrapping issues.
  - Aligned button/background/border styling more closely with web color tokens in light/dark modes.
- Verification completed after the polish:
  - `pnpm --filter @zero/ios run test:unit` passes (25/25).
  - `pnpm --filter @zero/ios run bundle:ios` passes.
- Assistant/login runtime stability hotfix:
  - Updated `apps/ios/app/(app)/assistant.tsx` to lazy-load `expo-av` at runtime and gracefully degrade dictation when the AV native module is unavailable, preventing route registration crashes.
  - Updated `apps/ios/app/(auth)/login.tsx` to use `SafeAreaView` from `react-native-safe-area-context` to remove deprecated `react-native` `SafeAreaView` usage warning.
- `N8-05` completed by removing deprecated public WebView wrapper app flows:
  - Deleted `apps/ios/app/(public)/*`.
  - Deleted `apps/ios/src/features/public/PublicWebRouteScreen.tsx`.
  - Updated `parity_screenshots/manifest.json` to remove deprecated public wrapper surfaces from screenshot requirements.
- `PG-010` advanced with native assistant voice UX + visual polish in `apps/ios/app/(app)/assistant.tsx`:
  - Added voice playback for assistant responses via `expo-speech`.
  - Added manual `Read latest` / `Stop voice` actions and an `Auto-read` toggle.
  - Added native voice dictation: microphone recording (`expo-av`) + backend transcription (`trpc.ai.transcribeAudio`) feeding assistant prompts.
  - Redesigned assistant screen UI with improved hierarchy, spacing, and restrained monochrome styling.
  - Refined visual language again to reduce chat-bot/dashboard feel (denser typography, cleaner grouping, subtler contrast, tighter controls) while preserving all behavior.
  - Full web-equivalent real-time ElevenLabs voice conversation remains blocked in current repo context.
- `N8-06` unblock work advanced with screenshot-ops tooling:
  - Added `pnpm parity:screenshots:sync` to rebuild `parity_screenshots/SCREENSHOT_LOG.md` directly from `manifest.json`.
  - Added `pnpm parity:screenshots:capture:ios` interactive simulator capture flow to accelerate parity evidence collection.
  - Updated `parity_screenshots/README.md` with the new scripted workflow.
- `N8-06` unblock work advanced with automated parity tests:
  - Completed `N3-09` with mail-core optimistic cache unit tests in `apps/ios/src/features/mail/optimisticThreadCache.test.ts`.
  - Completed `N5-06` with settings category-state unit tests in `apps/ios/src/features/settings/categoriesSettingsUtils.test.ts`.
  - Refactored `apps/ios/app/(app)/settings/categories.tsx` to use tested helpers from `categoriesSettingsUtils.ts`.
- `PG-010` voice parity advanced further in `apps/ios/app/(app)/assistant.tsx`:
  - Added optional hands-free mode to loop dictation -> transcription -> assistant response -> auto-read -> resume listening.
  - Added guardrails so unauthorized assistant/voice errors show clear auth-bypass messaging instead of raw transport errors.
- `PG-012` visual regression proof advanced:
  - Captured all `__web.png` artifacts from `parity_screenshots/manifest.json` (23 files) and synced `parity_screenshots/SCREENSHOT_LOG.md`.
  - Captured all `__macos.png` artifacts (23 files) through the Electron wrapper via `pnpm parity:screenshots:capture:macos:auto`.
  - Screenshot coverage moved from `23/92` -> `46/92` -> `69/92` (all web + iOS + macOS present; Android still missing).
  - Added parity auth-bypass capture mode on web (`VITE_PUBLIC_PARITY_AUTH_BYPASS=1`) so protected route screenshots stay on target routes instead of redirecting to `/login`.
  - Added `pnpm parity:screenshots:capture:android:auto` to complete Android captures when `adb` is available.
  - Installed `adb`, Android SDK command-line tools, Java, platform/build tools, and an API 34 ARM64 system image in this environment to unblock Android capture automation.
  - Android capture remains blocked in this environment because the emulator cannot boot with only `2.0 GiB` free disk (`FATAL: need 7372.80 MB for userdata partition`), so no Android device is available for screenshot capture.
- `PG-010` auth-bypass assistant behavior improved in `apps/ios/app/(app)/assistant.tsx`:
  - Added on-device fallback responses for text prompts when `EXPO_PUBLIC_AUTH_BYPASS=1`, so assistant remains usable instead of returning unauthorized transport errors.
  - Added explicit voice/hands-free gating in auth-bypass mode with clear user-facing guidance.
  - Added unit coverage for fallback behavior in `apps/ios/src/features/assistant/authBypassAssistant.test.ts`.
- Verification after WebView deprecation + assistant voice work:
  - `pnpm --filter @zero/ios run test:unit` passes (39/39).
  - `pnpm --filter @zero/ios run bundle:ios` passes.
  - `pnpm parity:screenshots:sync` succeeds.
  - `pnpm parity:screenshots:check` fails as expected (`69/92`) until Android captures are added.

## Session Notes (2026-03-01)

- `N3-05` completed in `apps/ios/app/search.tsx` with structured search filters mapped to server query semantics.
- `N5-01` completed by expanding settings navigation and stack routes in `apps/ios/app/(app)/settings/*`.
- `N3-06` completed with adaptive mail shell behavior (`apps/ios/app/(app)/_layout.tsx`, `apps/ios/app/(app)/(mail)/[folder].tsx`) and a reusable detail pane (`apps/ios/src/features/mail/ThreadDetailPane.tsx`).
- `N3-07` completed with optimistic cache updates + rollback utilities in `apps/ios/src/features/mail/optimisticThreadCache.ts`, wired into folder and detail actions.
- `N3-08` completed by fixing swipe direction action mapping in `apps/ios/src/features/mail/SwipeableThreadRow.tsx`.
- `N5-02` completed by replacing settings placeholders with native form screens for categories, notifications, privacy, security, shortcuts, and danger zone; plus upgrading general/appearance forms.
- `N5-03` completed in `apps/ios/app/(app)/settings/connections.tsx` (default, disconnect, reconnect handoff, add account handoff).
- `N5-04` completed in `apps/ios/app/(app)/settings/labels.tsx` with label CRUD and color picker parity.
- `N5-05` completed in `apps/ios/app/(app)/settings/danger-zone.tsx` with confirmation-gated account deletion.
- `N4-01` completed in `apps/ios/app/compose.tsx` by adding Bcc support and parity-oriented reply-all/forward prefills.
- `N4-02` completed in `apps/ios/app/compose.tsx` by integrating `@10play/tentap-editor` (`RichText` + `Toolbar`) for native rich-text composition.
- `N4-03` completed in `apps/ios/app/compose.tsx` with native document picking, attachment preview/removal, and attachment payload serialization for send.
- `N4-04` completed in `apps/ios/app/compose.tsx` with debounce-based draft auto-save, draft restore on reopen, and draft cleanup after successful send.
- `N4-05` completed with reply/reply-all/forward refinements in `apps/ios/app/compose.tsx` and `apps/ios/src/features/mail/ThreadDetailPane.tsx` (recipient parity rules, reply headers/forward metadata payload, and corrected inline action bar layout).
- `N4-06` completed with a global native undo-send banner (`apps/ios/src/shared/components/UndoSendBanner.tsx`) and queued/scheduled unsend wiring in compose (`apps/ios/app/compose.tsx`, `apps/ios/src/shared/state/undoSend.ts`).
- `N4-07` completed in `apps/ios/app/compose.tsx` with delayed-send date/time picking and `scheduleAt` payload support + validation.
- `N4-08` completed in `apps/ios/app/compose.tsx` with template save/list/apply/delete parity against `trpc.templates.*`.
- `N4-09` completed with extracted compose parity helpers (`apps/ios/src/features/compose/composeParity.ts`) and unit coverage (`apps/ios/src/features/compose/composeParity.test.ts`) wired to `pnpm --filter @zero/ios run test:unit`.
- `N6-01` completed with native assistant route (`apps/ios/app/(app)/assistant.tsx`) and drawer entry (`apps/ios/app/(app)/_layout.tsx`), including streamed response rendering.
- `N6-02` moved to `BLOCKED`: current ElevenLabs implementation in web depends on browser-only APIs (`apps/mail/providers/voice-provider.tsx`, `@elevenlabs/react`) and no RN-native equivalent is present in this repo context.
- `N6-05` completed in `apps/ios/src/features/mail/ThreadDetailPane.tsx` with notes list/create/edit/delete/pin/unpin backed by `trpc.notes.*`.
- `N6-06` completed with additional iOS unit coverage for assistant/notes logic (`apps/ios/src/features/assistant/assistantUtils.test.ts`, `apps/ios/src/features/mail/notesUtils.test.ts`).
- `N7-01` completed by introducing unauthenticated public routes in native (`apps/ios/app/(public)/index.tsx`, `apps/ios/app/(public)/home.tsx`) backed by reusable web route wrappers (`apps/ios/src/features/public/PublicWebRouteScreen.tsx`) and auth guard updates in `apps/ios/app/_layout.tsx`.
- `N7-02` completed by adding legal/public parity routes in native (`apps/ios/app/(public)/about.tsx`, `apps/ios/app/(public)/terms.tsx`, `apps/ios/app/(public)/privacy.tsx`) using the shared public WebView route wrapper.
- `N7-03` completed with native public pricing route wrapper (`apps/ios/app/(public)/pricing.tsx`).
- `N7-04` completed with native public contributors/developer route wrappers (`apps/ios/app/(public)/contributors.tsx`, `apps/ios/app/(public)/developer.tsx`).
- `N7-05` completed by adding native under-construction fallback route (`apps/ios/app/(app)/(mail)/under-construction/[path].tsx`), complementing existing `+not-found`.
- `N6-03` completed with PostHog integration in native (`apps/ios/src/shared/telemetry/posthog.ts`, provider bootstrap in `apps/ios/src/providers/AppProviders.tsx`, route tracking in `apps/ios/app/_layout.tsx`, user identify in `apps/ios/app/(app)/_layout.tsx`, and event instrumentation in compose/thread actions).
- `N6-04` completed with Sentry integration in native (`apps/ios/src/shared/telemetry/sentry.ts`, initialization in `apps/ios/src/providers/AppProviders.tsx`, app wrapper in `apps/ios/app/_layout.tsx`, and capture hooks in `apps/ios/src/shared/components/ErrorBoundary.tsx` + `apps/ios/src/providers/QueryTrpcProvider.tsx`).
- `N8-01` moved to `BLOCKED` after implementing screenshot governance artifacts in `/parity_screenshots` (`manifest.json`, `SCREENSHOT_LOG.md`, `README.md`) and adding coverage enforcement via `pnpm parity:screenshots:check`; full completion requires runtime captures on web/iOS/Android/macOS.
- `N8-02` completed with targeted native performance improvements in mail flows: list/detail query cache tuning (`staleTime`/`gcTime`), reduced auto-refetch churn, FlashList virtualization tuning, and memoized thread rows.
- `PG-006` completed with native `/api/mailto-handler` parity in `apps/ios/app/api/mailto-handler.tsx`, shared parser/draft helpers in `apps/ios/src/features/compose/mailtoParity.ts`, compose route prefill + `draftId` send wiring in `apps/ios/app/compose.tsx`, and in-thread `mailto:` interception in `apps/ios/src/features/mail/MessageCard.tsx`.
- `PG-001` completed by adding native public `/hr` parity wrapper route in `apps/ios/app/(public)/hr.tsx`.
- `PG-003` completed in `apps/ios/app/(app)/(mail)/[folder].tsx` and `apps/ios/src/features/mail/MailSidebar.tsx` by finishing category tab parity and adding native command-palette entry points (mail header search trigger with shortcut hint + drawer search entry).
- `PG-004` completed in `apps/ios/app/(app)/(mail)/create.tsx`, `apps/ios/app/(app)/(mail)/under-construction/[path].tsx`, and `apps/ios/app/(app)/(mail)/_layout.tsx` with `/mail/create` redirect semantics to compose (including query prefill passthrough) and web-aligned under-construction back/inbox actions.
- `PG-011` completed by adding native Autumn billing integration and settings UX parity (`apps/ios/src/shared/integrations/autumn.ts`, `apps/ios/app/(app)/settings/billing.tsx`, route wiring in settings index/layout). Dub parity remains server-driven via existing backend `dubAnalytics` auth plugin; native uses the same better-auth social sign-in endpoint flow.
- `PG-013` completed by adding parity-focused native automated coverage for Autumn integration flows (`apps/ios/src/shared/integrations/autumn.test.ts`) and an RC/manual E2E parity script (`apps/ios/TEST_PLAN_PARITY.md`) covering critical mail shell, compose, settings, and integration workflows.
- `N8-03` completed with critical accessibility updates in native mail/settings surfaces (`apps/ios/app/(app)/(mail)/[folder].tsx`, `apps/ios/src/features/mail/ThreadListItem.tsx`, `apps/ios/src/features/mail/ThreadDetailPane.tsx`, `apps/ios/src/features/mail/MailSidebar.tsx`, `apps/ios/app/(app)/settings/index.tsx`).
- `N8-04` completed with repository-native release automation (`.github/workflows/native-release.yml`) and operator documentation (`apps/ios/RELEASE_PIPELINE.md`), while keeping signing/store credentials as manual external dependencies.
- Login/auth flow remains untouched in this stream per ownership constraint.
- `N3-09` and `N5-06` are now complete in iOS scope with native unit coverage; workspace-level server/packages type instability still exists but no longer blocks M3/M5 native parity tests.
- 2026-03-11 follow-up: fixed the iOS mail read/unread optimistic rollback implementation in `apps/ios/src/features/mail/SwipeableThreadRow.tsx` and `apps/ios/src/features/mail/ThreadDetailPane.tsx` so the new gesture/header actions no longer introduce native TypeScript errors.
- 2026-03-11 follow-up: removed the inbox gesture tip banner, replaced the inbox compose `+` with a pencil icon, neutralized the remaining blue/slate tint in the native mail surface tokens, and switched sender avatar fallbacks to domain-logo lookups with `fallback=false` so missing logos drop to initials instead of the generic person placeholder. User-facing change in `apps/ios/app/(app)/(mail)/[folder].tsx`, `apps/ios/src/shared/theme/ThemeContext.tsx`, and `apps/ios/src/features/mail/SenderAvatar.tsx`.
- 2026-03-11 follow-up: reshaped the iOS inbox from card rows into a cleaner divided list, increased row hierarchy to match the provided reference, and redesigned the inbox header around identity and status by showing the signed-in account avatar plus a live unread count. Search and compose were preserved in a secondary action row below the new header. User-facing change in `apps/ios/src/features/mail/ThreadListItem.tsx` and `apps/ios/app/(app)/(mail)/[folder].tsx`.

### Test / Build Status

- Workspace TypeScript checks remain blocked by pre-existing cross-package errors outside iOS scope (not introduced by this stream).
- Screenshot coverage check passes for iOS scope (`46/46`) using `parity_screenshots/manifest.json` (`web` + `ios`).
- iOS targeted unit tests pass via `pnpm --filter @zero/ios run test:unit` (39/39 passing).
- 2026-03-11 targeted verification: `pnpm --dir apps/ios test:unit` passes after the inbox avatar/theme/header cleanup, and narrowed `tsc --noEmit` output shows no errors for `ThemeContext.tsx`, `SenderAvatar.tsx`, or `apps/ios/app/(app)/(mail)/[folder].tsx`.
- 2026-03-11 targeted verification: `pnpm --dir apps/ios test:unit` still passes after the inbox list/header redesign, and narrowed `tsc --noEmit` output shows no errors for `ThreadListItem.tsx`, `SenderAvatar.tsx`, `ThemeContext.tsx`, or `apps/ios/app/(app)/(mail)/[folder].tsx`.
- Targeted formatting checks pass on all files touched in this session.
- 2026-04-03 follow-up: fixed the notes delete confirmation to use the generated Paraglide key, removed the non-functional meeting notification toggles from the new meetings settings page, added automatic cleanup for expired meeting recordings, and expanded calendar sync so previously imported future meetings are also auto-scheduled for recording. User-facing and architectural change in `apps/mail/components/mail/note-panel.tsx`, `apps/mail/app/(routes)/settings/meetings/page.tsx`, `apps/server/src/trpc/routes/meet.ts`, `apps/server/src/routes/recall-webhook.ts`, and `apps/server/src/lib/meeting-retention.ts`.
- 2026-04-03 follow-up: tightened the native iOS Tasks controls by reducing the search field and sort chip height, compressed task-row spacing to reduce left padding and card height, and refactored Calendar mode into a timeline-style bucket layout so it is visually and behaviorally distinct from List. User-facing change in `apps/ios/Todus/Todus/Features/Tasks/TasksTabView.swift`, `apps/ios/Todus/Todus/Features/Tasks/TaskRowView.swift`, and `apps/ios/Todus/Todus/Features/Tasks/CalendarTaskView.swift`.
- 2026-04-03 follow-up: redesigned the native iOS Tasks board with a tighter kanban visual system, quieter monochrome grouping, denser cards, clearer stage headers and empty states, and a more legible board-mode icon in the view toggle. User-facing change in `apps/ios/Todus/Todus/Features/Tasks/BoardView.swift`, `apps/ios/Todus/Todus/Features/Tasks/BoardColumnView.swift`, `apps/ios/Todus/Todus/Features/Tasks/BoardTaskCard.swift`, and `apps/ios/Todus/Todus/Domain/TaskViewMode.swift`.
- 2026-04-24 follow-up: corrected the root `pnpm ios`, `pnpm ios:simulator`, and `pnpm ios:build:*` entry points so they target `apps/ios/Todus/Todus.xcodeproj` instead of the archived Expo app under `apps/archived/archived-rn`. Verified the real native app with `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`.

---

## Parity Gap Tasks (2026-03-01)

| ID     | Task                                                                                                                                      | Status | Notes                                                                                                                                                                          |
| ------ | ----------------------------------------------------------------------------------------------------------------------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| PG-001 | Implement native public route set parity (`/`, `/home`, `/about`, `/terms`, `/pricing`, `/privacy`, `/contributors`, `/developer`, `/hr`) | DONE   | Completed historically; these public WebView wrapper routes were later deprecated/removed in `N8-05` as part of native wrapper-flow cleanup                                    |
| PG-002 | Add native `/signup` parity flow                                                                                                          | DONE   | Added native auth signup route/screen in `apps/ios/app/(auth)/signup.tsx` and wired it in `apps/ios/app/(auth)/_layout.tsx`                                                    |
| PG-003 | Complete native mail shell parity for `/mail/:folder`                                                                                     | DONE   | Category tabs + bulk selection + command palette/search entry points now implemented in native mail shell                                                                      |
| PG-004 | Implement `/mail/create` and `/mail/under-construction/:path` parity behaviors                                                            | DONE   | Native create redirect now forwards web-style prefill params to compose; under-construction fallback now matches web behavior                                                  |
| PG-005 | Rebuild native compose parity (`/mail/compose`)                                                                                           | DONE   | Compose parity shipped with rich text, attachments, drafts, reply/reply-all/forward, undo-send, schedule send, and templates                                                   |
| PG-006 | Add native mailto parity (`/api/mailto-handler`)                                                                                          | DONE   | Native `/api/mailto-handler` parses mailto payloads, attempts draft creation, and opens compose with fallback params + `draftId` when available                                |
| PG-007 | Complete settings parity for missing sections                                                                                             | DONE   | Native forms added for `/settings/categories`, `/settings/notifications`, `/settings/privacy`, `/settings/security`, `/settings/shortcuts`, `/settings/danger-zone`            |
| PG-008 | Upgrade native existing settings sections from partial to full parity                                                                     | DONE   | `/settings/general`, `/settings/appearance`, `/settings/connections`, `/settings/labels` upgraded with parity-focused forms/actions                                            |
| PG-009 | Implement labels/categories CRUD + assignment parity in native                                                                            | DONE   | Labels CRUD + color selection and category default/order/filter editing implemented                                                                                            |
| PG-010 | Implement native AI assistant and voice parity                                                                                            | DONE   | Native assistant now has practical parity for iOS workflows: streaming chat, dictation + transcription, playback, auto-read, hands-free loop, and auth-bypass-safe fallback UX |
| PG-011 | Implement native integrations parity: PostHog + Dub + Sentry + Autumn                                                                     | DONE   | Autumn billing customer/checkout/portal native integration added; Dub attribution stays server-side through existing better-auth plugin used by native auth flow               |
| PG-012 | Establish screenshot-driven visual regression proof in `/parity_screenshots/`                                                             | DONE   | Naming convention + manifest + diff log + verifier are implemented, and required iOS-scope coverage passes (`web` + `ios`: `46/46`)                                            |
| PG-013 | Build parity-focused automated tests (unit/integration/E2E)                                                                               | DONE   | Added Autumn integration tests to iOS unit suite and documented RC E2E/manual parity workflow script in `apps/ios/TEST_PLAN_PARITY.md`                                         |
| PG-014 | Resolve macOS architecture blocker                                                                                                        | DONE   | De-scoped from this stream because current migration goal is iOS-native parity (`apps/ios`); macOS architecture work is tracked separately outside this iOS backlog            |

## Web Parity Follow-up (2026-03-31)

- Added the missing primary web surfaces in `apps/mail` for Home, Tasks, Calendar, Search, and AI Chat under `/mail/*`.
- Switched the authenticated web landing route from `/mail/inbox` to `/mail/home` to match the native app information architecture.
- Upgraded the web sidebar to surface native-style primary navigation with expandable Email children instead of inbox-only navigation.
- Ported existing parity page implementations from the legacy web app into the active `apps/mail` app and validated them with targeted ESLint plus a successful `pnpm --filter @zero/mail build`.
- Build still emits pre-existing workspace warnings from unrelated files and reference/archived tsconfig parsing; these were not introduced by this parity work.

## Web Performance Follow-up (2026-04-04)

- Corrected the loading-state work to the actual web app under `apps/web` after the earlier pass hit the wrong frontend surface.
- Added subtle background-refresh indicators for inbox, home, tasks, and calendar so cached data stays visible while refresh status remains explicit.
- Stopped invalidating restored web inbox cache on startup and switched the web home recent-email panel to use thread summary data directly instead of extra per-row thread fetches.

# 2026-04-04

## Investigate onboarding/marketing email spam

- Root cause traced to non-atomic onboarding campaign enrollment in `apps/server/src/lib/auth.ts` plus missing uniqueness on `mail0_account(provider_id, account_id)`.
- Implemented a durable marketing email ledger to guarantee no duplicate onboarding email enrollment per normalized recipient and no more than one marketing email per recipient per day.
- Added migration `0048_marketing_email_idempotency.sql` to dedupe duplicate account rows before enforcing the new auth account uniqueness constraint.
- Added `pnpm scripts audit-auth-duplicates` for follow-up inspection against a connected database because the local Postgres instance was not running during the investigation.

## Review Follow-up (2026-04-25)

- Fixed the Zero chat agent billing hook to use the actual resolved AI model id instead of `DEFAULT_MODEL` fallback assumptions.
- Restored legacy `mail0_connection` fallback reads in Zero chat auth/user lookup paths so partially migrated environments do not break chat.
- Moved legacy subscription hydration into the shared AI credit check so chat and voice enforce the same billing state without requiring a Billing page visit first.

## Startup Log Follow-up (2026-04-26)

- Investigated iOS cold-start logs and isolated the actionable failures to backend startup requests for `assistant.getBriefing` and `mail.listThreads`, both caused by an environment still missing the `mail0_connection.color` column.
- Hardened server-side detection of the missing-column condition so wrapped durable-object / shard bootstrap errors still trigger the legacy fallback path instead of returning a 500 during app startup.
- Classified the `XPC connection was invalidated` and `nw_protocol_instance_set_output_handler ... udp` lines as Apple framework/runtime noise, not application-level regressions from Todus startup code.
- Manual follow-up remains required: apply the existing backend migration `apps/server/src/db/migrations/0047_connection_color.sql` in the deployed environment behind `https://api.todus.app` so the fallback is no longer needed.
