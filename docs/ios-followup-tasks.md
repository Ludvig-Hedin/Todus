# iOS Follow-up Tasks — post-audit handoff

> **UPDATE (2026-07-08, later same session):** Tasks 1–4 and 7 below were implemented and are live (commit history: dynamic tab bar, in-composer attachment picker, all-mail search scope, session-persistent meeting Q&A, micro-nits). Only Task 5 (server deploy — ops) and Task 6 (device smoke test — human-in-the-loop) remain; specs kept below for reference.
>
> Created 2026-07-08 after the iOS triple audit (UX assessment + UX polish + bug hunt; commits `3ebe558a`, `959b6cfc`, `33639d4d`, `dd040cc7`). All ~75 audit findings are fixed and adversarially verified. The items below are the intentionally remaining product/feature work, written as self-contained specs so any agent/session can pick one up cold. Each task lists exact files, the investigation already done, and known gotchas.
>
> Context docs: `AGENT_CONTEXT.md` (repo map), `CLAUDE.md` (iOS build commands), `CODE_REVIEW_BACKLOG.md` (audit history).
> Build check: `cd apps/ios/Todus && xcodebuild -project Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' -configuration Debug build`.

---

## Task 1 — Wire the dynamic tab bar (BH-0613-6)

**Goal:** `MainTabView` renders the user's chosen tabs from `services.tabBarTabs` (home-first, max 4) plus a "More" tab, instead of the fixed 6-tab set. Un-gate the existing customization UI.

**Current state (all investigated):**
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift:163-209` — fixed `TabView(selection: $selectedTab)` with six hardcoded `.tabItem` entries (old syntax). FABs are overlaid separately and are unaffected.
- `App/AppServices.swift:411-421, 743-757` — `services.tabBarTabs: [AppTab]` already persists/loads (UserDefaults `TaskApp.tabBarTabs`, falls back to `AppTab.defaultNavTabs`, clamps to 4).
- `Navigation/AppTab.swift:52` — `defaultNavTabs = [.home, .tasks, .email, .calendar]` (the intended default).
- `Features/Settings/TabBarCustomizationView.swift` — fully built editor (add/remove/reorder, `save()` at :137 guarantees home-first + max 4, has haptics). Currently reachable only behind the developer allowlist.
- `Features/MoreSheetView.swift` — **currently unreachable dead UI** (nothing presents it since the custom tab bar was removed). It already filters entries by `!services.tabBarTabs.contains(...)` and takes an `onNavigate: (AppTab) -> Void`.
- Entry points to un-gate after wiring: `Features/Settings/SettingsView.swift:~820` and `Features/MoreSheetView.swift:~69` (both wrapped in `if services.isDeveloperModeUIAvailable` with comments referencing BH-0613-6).

**Recommended design (min iOS 18, so the new `Tab` API is available):**
1. Convert the `TabView` body to the iOS-18 `Tab(value:)` builder syntax and keep **all six content tabs instantiated**, hiding non-active ones with `TabContent.hidden(_:)`:
   ```swift
   TabView(selection: $selectedTab) {
       Tab(value: AppTab.calendar) { calendarTabContent } label: { Label(AppTab.calendar.title, systemImage: AppTab.calendar.inactiveIcon()) }
           .hidden(!barTabs.contains(.calendar))
       // … repeat for home/tasks/email/docs/meetings …
       Tab(value: AppTab.more) { MoreTabView(onNavigate: { services.navigateTo = $0 }) } label: { Label("More", systemImage: "ellipsis") }
   }
   ```
   where `barTabs = services.tabBarTabs` (already validated). Keeping hidden tabs instantiated means `services.navigateTo = .docs` (used by Home/global search/AI cards) still works — a hidden tab can be selected programmatically; its content shows without a bar highlight.
2. Add `case more` to `AppTab` (`Navigation/AppTab.swift`) with title "More", icon "ellipsis". It's `Codable` by rawValue — new case is backward-compatible. Exclude it from `TabBarCustomizationView.availableTabs` (`:18` — currently filters out `.create`/`.ai`; add `.more`).
3. Repurpose `MoreSheetView` as the More tab's content (rename or wrap). **Gotcha:** `DocsListView` owns a `NavigationSplitView` internally — do NOT nest it inside another `NavigationStack` (see the comment at `MoreSheetView.swift:40-43`); navigate via `onNavigate(.docs)` instead of pushing.
4. `MainTabView.visibleContentTabs` (`:332`) currently gates restored selection — keep all six content tabs valid there.
5. Un-gate the two "Customize Tab Bar" entry points and delete their BH-0613-6 comments. Since `MainTabView` now reads `services.tabBarTabs` (an `@Observable` property), saving in the editor takes effect immediately.
6. Update `RootView.swift:54-61` NOTE (it documents the removed onboarding step referencing BH-0613-6) and `CODE_REVIEW_BACKLOG.md`'s "Deferred (product decisions)" entry.

**Acceptance:** default fresh install shows Home/Tasks/Email/Calendar + More; customization changes the bar live; Docs/Meetings reachable via More; `navigateTo` deep links still land on hidden tabs; welcome-tour copy stays truthful (it no longer promises this feature — leave as is or re-add a card).

**Effort:** ~half day incl. testing. Risk: medium (touches app shell; test tab restore via `@SceneStorage`, FAB overlay, hideTabBar behavior).

---

## Task 2 — In-composer attachment picker

**Goal:** Let users attach files/photos directly inside `EmailComposeView` (attachments currently enter only when seeded from `CreateSheet`, though upload now works end-to-end).

**Current state:**
- `Features/Email/EmailComposeView.swift` — `seededAttachmentNames: [String]` (`:~17`) renders `attachmentChipsRow` and is passed to `emailService.sendEmail(_:fromEmail:attachmentNames:)`, which serializes files inline (base64, matches server `serializedFileSchema`). Chip removal + confirmation already exist.
- Reference implementation to copy: `Navigation/CreateSheet.swift:165-200` — `.photosPicker`, `.fileImporter` (multi-select), `.fullScreenCover` camera (`CameraPicker`), all appending to `pendingAttachments` via `AttachmentService.shared.importFile/saveImage`. `TaskDetailSheet.swift:89-147` has the same trio with a `confirmationDialog` chooser.

**Work:**
1. Add a paperclip button to the compose toolbar (formatting toolbar row, `formattingToolbar` — or the nav bar) opening the same three-way chooser (`Take Photo` / `Choose from Library` / `Upload File`).
2. Append resulting filenames to `seededAttachmentNames` (chips + upload then work with zero further changes).
3. Cleanup parity: files added in-composer but removed (or compose cancelled) should be deleted from disk — mirror `TaskDetailSheet`'s session-added tracking (compare against the seeded initial set; see its Cancel handler at `:74-84` and the remove handler at `:176-191`).
4. Consider a total-size guard (~20 MB) with a friendly error — Gmail rejects >25 MB; the send serializes base64 in-memory.

**Effort:** 2–4 h. Risk: low (isolated view work; upload path already proven).

---

## Task 3 — Widen email search scope beyond the inbox folder

**Goal:** Global search and the inbox's server search currently query `folder: "inbox"` only. "Search everything" should cover archived/sent mail.

**Current state:**
- `Services/Email/EmailService.swift` — `searchThreadsServer(query:limit:)` uses `ListThreadsInput(folder: "inbox", q:, maxResults:, cursor:)`; the inbox debounce path (`loadThreads(query:)`) likewise searches the **currently selected folder**.
- Backend: `apps/server/src/trpc/routes/mail.ts` `listThreads` — investigate how `q` interacts with `folder` (the iOS side was not able to confirm whether `q` searches across folders server-side or is folder-scoped). Check `getZeroAgent(...).listThreads` / the DB query in the driver for whether a folder like `"archive"`/`"all"` exists.

**Work options (pick after reading the server):**
- **A (preferred, server):** support `folder: "all"` (or make `q` ignore folder) in `listThreads`; then change `searchThreadsServer` to pass it. One-line client change.
- **B (client-only):** fan out `searchThreadsServer` over `["inbox", "archive", "sent"]` in parallel and merge/dedupe by thread id (the merge/dedupe pattern already exists in `GlobalSearchView.emailResults`).
- Update the pending copy "Searching all mail…" in `GlobalSearchView` if scope stays partial.

**Effort:** 1–3 h depending on option. Risk: low.

---

## Task 4 — Persist meeting Q&A

**Goal:** The "Ask about this meeting" thread (`Features/Meetings/MeetingDetailView.swift:22`, `qaMessages` plain `@State`) resets on every navigation. A hint ("Answers aren't saved when you leave this meeting") was added, but persistence is the real fix.

**Work (two tiers):**
1. **Session cache (cheap):** move `qaMessages` into `MeetingsService` keyed by meeting id (`var qaThreads: [String: [(role: String, content: String)]]`), so back-and-forth navigation within a session retains the thread. Update the hint copy to "Saved for this session."
2. **Durable (needs backend):** persist via the existing AI conversation store (`ai.saveConversation`, used by `AIChatService`) with a `meetingId` tag, and load on open. Requires a small server route addition or reuse of `ai.getConversation`.

**Effort:** tier 1: ~1 h. tier 2: ~half day.

---

## Task 5 — Deploy `apps/server` before the next iOS release (ops)

The audit added a **`clientSendId` idempotency key** to `mail.send` (KV-deduped on both immediate and scheduled paths, `apps/server/src/trpc/routes/mail.ts`). iOS `DraftService` sends the draft's stable id and now auto-retries drafts stuck in `"sending"` — that retry is only duplicate-safe once the server is deployed (pre-deploy, zod strips the unknown key and behavior matches the old semantics).

- Deploy: `bun deploy:backend` (needs CF auth for account `7e953f…` — see memory note `cloudflare-deploy-auth`; local wrangler OAuth may hit error 10000; `wrangler deploy --dry-run` is the safe check).
- Order: server first, then ship the iOS build.

---

## Task 6 — Device smoke test (verification debt)

Everything is source-verified + simulator-build-green, but two flows deserve a runtime pass on a device/simulator with a real account:

1. **Attachment round-trip:** receive an email with a PDF + image → tap each card → downloads with spinner → previews/shares → dismiss deletes the temp file. Compose with an attachment from CreateSheet → send → recipient receives the file.
2. **Idempotent send:** with the server deployed, kill the app mid-send (`syncState == "sending"`), relaunch, reconnect → draft retries → exactly one email delivered.
3. Quick regression sweep of: calendar tap-slot → CreateSheet pre-filled time; capture toast; guest onboarding progress pill; AI permission toggle taking effect without relaunch.

`--ui-testing` launch arg seeds an authed session without a backend (see memory note `ios-ui-testing-launch-args`) — useful for the UI-only parts.

---

## Task 7 — Micro-nits (batch into any nearby PR, not worth solo sessions)

- `Data/AppConfiguration.swift` `hasSupabaseBackend`: a whitespace-only `supabaseURL` string parses non-nil — trim before `URL(string:)` (verify-ai note; currently unreachable in prod configs).
- `EmailService.composeBodyToHTML`: links aren't auto-linked (plain URLs ship as text). Add URL detection → `<a href>` if desired.
- `MeetingsService.syncFromCalendar()` exposes no error state — Home/Meetings empty-state can't distinguish "no meetings" from "sync failed" (both show the sync prompt). Add a `lastSyncError` published property + surface in `MeetingsListView`/`HomeView` meetings section.
