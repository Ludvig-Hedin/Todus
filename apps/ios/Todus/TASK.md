# Todus — Task Board

## Current Tasks

### ✅ Recently Completed
- [x] **IOS-084** — Close residual iOS performance/reliability findings from the 2026-07-22 audit
  - Added bounded Google Calendar pagination and preserved cached sources on transient refresh failures
  - Moved camera attachment encoding/writes off-main and indexed Docs hierarchy rendering
  - Serialized Docs title saves and hardened email preview decoding
  - Fixed local-model runtime detection/scan races, notification error visibility, EventKit concurrency warnings, and required-tab dragging
  - Replaced blank hidden overflow tabs with real native More destinations and stabilized Settings/Docs UI coverage
  - Made task-capture rollback explicit: only backend `422` validation can delete the local capture
  - Verified 123 iOS unit tests and all 10 native UI tests on a dedicated clean simulator
- [x] **IOS-083** — Apply iOS CodeRabbit review fixes across folders/tasks/AI/widgets/voice/api and remove tracked user-specific Xcode state
  - Fixed stale `restrictToInbox` refreshes in board/table views
  - Prevented duplicate folder item inserts in pickers + service layer
  - Added destructive delete confirmations for folder management surfaces
  - Corrected the native Gemini Live model identifier to `gemini-live-2.5-flash-native-audio`
  - Hardened widget/day-boundary logic, attachment cleanup timing, avatar-cache flushing, AI undo completion, and voice startup disconnect handling

### 🔴 Blocked
- [ ] **IOS-001** — Create Xcode project in Xcode IDE, set bundle ID `com.ludvighedin.todus`, team `XDBG7P4V96`
  - *Requires:* Manual Xcode work
- [ ] **IOS-002** — Add all Swift source files to Xcode project target
  - *Requires:* IOS-001
- [ ] **IOS-003** — Add CalendarKit v1.1.7 as SPM dependency
  - *Requires:* IOS-001
- [x] **IOS-004** — Verify project compiles on iOS 18 simulator
  - *Requires:* IOS-002, IOS-003

### 🟡 Ready to Start

#### Backend — Remaining
- [ ] **BE-003** — Run Drizzle migration to create tables in PostgreSQL
- [ ] **BE-009** — Add `task.parse` route (AI text parsing)
  - Input: rawText, locale, timezone
  - Output: { title, description?, priority?, dueDate?, folder? }
- [ ] **BE-014** — Add `POST /api/ai/chat` SSE streaming endpoint
  - Port system prompt from Supabase edge function
  - Support task tool calls (create, update, delete)
- [ ] **BE-015** — Add email tool calls to AI chat (send_email, search_email)
- [ ] **BE-016** — Add calendar tool call (create_event)
- [ ] **BE-018** — Test all task endpoints via curl with Bearer token

---

#### iOS — Task Service (Migration)
- [ ] **IOS-021** — Create `TaskService.swift` (task CRUD via TodosAPIClient)
  - Replaces SupabaseSyncService
  - [x] create, update, delete, sync use authenticated `tasks.sync`
  - [x] hydrate paginated `tasks.list` upserts after folders without overwriting pending local edits
  - [x] reconcile explicit paginated server deletion tombstones without unsafe absence-based deletion
- [x] **IOS-022** — Rewire TaskCaptureService to use the unified tRPC task sync transport
- [x] **IOS-023** — Rewire AIChatService to use new backend endpoint
- [x] **IOS-024** — Add AI chat message retry + stable copy action row
- [x] **IOS-025** — Preserve AI mention context across saved chats, prune stale turns on retry, and hide raw spec JSON for spec-only replies
- [x] **IOS-026** — Cancel active streams before loading chat history, preserve metadata when duplicating chats, and restore assistant actions for spec-only replies

#### iOS — Navigation Testing
- [ ] **IOS-031** — Test TasksTabView works with all task features
- [ ] **IOS-032** — Test CalendarContainerView with EventKit permissions
- [ ] **IOS-033** — Test HomeView shows events + tasks
- [ ] **IOS-034** — Test CreateSheet creates tasks
- [ ] **IOS-035** — Test AI chat sheet opens from tab bar
- [ ] **IOS-036** — Add safe area insets for custom tab bar clearance
- [x] **IOS-080** — Remove runtime floating tab bar and keep only the native iOS tab bar
- [x] **IOS-081** — Restore the native tab bar center `+` action and remove Meetings from visible tabs
- [x] **IOS-082** — Restore the floating bottom-right AI FAB while keeping the native tab bar

#### iOS — Email Enhancements
- [ ] **IOS-047** — Add email section to HomeView (unread count + recent threads)
- [x] **IOS-048** — Wire "Email" type in CreateSheet → opens EmailComposeView

#### iOS — AI Expansion
- [ ] **IOS-050** — Add `create_event` tool call to AIChatService
- [ ] **IOS-051** — Add `send_email` tool call to AIChatService
- [ ] **IOS-052** — Add `search_email` tool call to AIChatService
- [ ] **IOS-053** — Inject events + emails into AI system prompt context
- [ ] **IOS-054** — Wire "Auto" mode in CreateSheet (AI decides type)

#### iOS — Polish
- [x] **IOS-077** — Mitigate startup/runtime hangs with EventKit pruning fix, startup throttling, task recompute tracing, and async attachment thumbnail loading
- [x] **IOS-079** — Simplify the task edit sheet with explicit field labels, clearer progress controls, and a lower-friction folder + attachment flow
- [ ] **IOS-060** — Dark mode audit across all new views
- [ ] **IOS-061** — HomeView loading skeletons
- [ ] **IOS-062** — HomeView pull-to-refresh
- [ ] **IOS-063** — Add email account management to Settings
- [ ] **IOS-064** — Add haptic feedback on tab switch, create, complete
- [ ] **IOS-065** — Verify tab bar liquid glass material appearance
- [ ] **IOS-066** — Unread email badge on email tab icon

#### iOS — Ship
- [ ] **IOS-070** — Configure code signing and provisioning profiles
- [ ] **IOS-071** — Update app icon
- [ ] **IOS-072** — Archive build
- [ ] **IOS-073** — Submit to TestFlight
- [ ] **IOS-074** — Test on physical device

---

## Backlog (macOS)
- [ ] **MAC-001** — Add macOS destination to Xcode project
- [ ] **MAC-002** — Adapt navigation to NavigationSplitView (sidebar)
- [ ] **MAC-003** — Replace CalendarKit with macOS-compatible calendar view
- [ ] **MAC-004** — Add platform conditionals (#if os(macOS))
- [ ] **MAC-005** — Toolbar and menu bar integration
- [ ] **MAC-006** — Keyboard shortcuts
- [ ] **MAC-007** — Test and polish macOS interactions
- [ ] **MAC-008** — Submit macOS build to TestFlight

---

## Completed
- [x] **SETUP-001** — Archive React Native code to `archived-rn/`
- [x] **SETUP-002** — Create directory structure for unified Swift app
- [x] **SETUP-003** — Copy all MiniTaskApp source files (48 files)
- [x] **SETUP-004** — Copy CalendarApp files (CalendarViewController, EKWrapper)
- [x] **SETUP-005** — Rename @main struct to TodosApp
- [x] **SETUP-006** — Create AppTab.swift (tab enum)
- [x] **SETUP-007** — Create CreateItemType.swift (create sheet type enum)
- [x] **SETUP-008** — Create EmailModels.swift (thread/message DTOs)
- [x] **SETUP-009** — Create MainTabView.swift (custom tab bar + FAB + AI button)
- [x] **SETUP-010** — Create TasksTabView.swift (extracted from RootView)
- [x] **SETUP-011** — Create CalendarContainerView.swift (UIViewControllerRepresentable)
- [x] **SETUP-012** — Create CalendarService.swift (shared EKEventStore actor)
- [x] **SETUP-013** — Create HomeView.swift (today dashboard skeleton)
- [x] **SETUP-014** — Create CreateSheet.swift (universal create with type selector)
- [x] **DOC-001** — Create design.md
- [x] **DOC-002** — Create features.md
- [x] **DOC-003** — Create plan.md
- [x] **DOC-004** — Create status_ios.md
- [x] **DOC-005** — Create status_macos.md
- [x] **DOC-006** — Create TASK.md
- [x] **BE-001** — Add `tasks` table to Drizzle schema
- [x] **BE-002** — Add `folders` table to Drizzle schema
- [x] **BE-004** — Create task TRPC routes (list, create, update, delete)
- [x] **BE-005** — Task create route
- [x] **BE-006** — Task update route
- [x] **BE-007** — Task delete route
- [x] **BE-008** — Task sync route (batch upsert/delete)
- [x] **BE-010** — Folder list route
- [x] **BE-011** — Folder create route
- [x] **BE-012** — Folder update route
- [x] **BE-013** — Folder delete route
- [x] **BE-017** — Register task + folder routes in TRPC router
- [x] **IOS-010** — Create AuthService.swift (@Observable, Better-Auth client)
- [x] **IOS-011** — Implement Apple Sign In in AuthService
- [x] **IOS-012** — Implement Google Sign In in AuthService
- [x] **IOS-013** — Implement email OTP in AuthService
- [x] **IOS-014** — Build AuthView.swift (onboarding screen with 3 sign-in buttons)
- [x] **IOS-015** — Handle `todus://auth-callback` deep link in TodosApp.swift
- [x] **IOS-016** — Update AppServices to use AuthService + new services
- [x] **IOS-020** — Create TodosAPIClient.swift (base HTTP client + TRPC helpers)
- [x] **IOS-030** — Wire MainTabView into RootView (auth → onboarding → main tabs)
- [x] **IOS-040** — Create EmailService.swift (@Observable, wraps TodosAPIClient)
- [x] **IOS-041** — Build EmailConnectView.swift (connect Gmail/Outlook)
- [x] **IOS-042** — Build EmailRowView.swift (sender initials, subject, snippet, time, swipe)
- [x] **IOS-043** — Build EmailInboxView.swift (list + search + pull-to-refresh + swipe)
- [x] **IOS-044** — Build EmailHTMLView (WKWebView wrapper for HTML bodies)
- [x] **IOS-045** — Build EmailThreadView.swift (message list + HTML rendering + reply)
- [x] **IOS-046** — Build EmailComposeView.swift (To, Subject, Body, Send + reply mode)
- [x] **IOS-075** — Preserve CreateSheet text when opening email compose
- [x] **IOS-076** — Respect Reminders sync direction for bootstrap + live edits
- [x] **IOS-077** — Treat Calendar `fullAccess` as connected in Settings
- [x] **IOS-078** — Refresh Gmail connection state after connect flow

---

## Discovered During Work
*(Add items here as they come up during implementation)*

- CalendarViewController uses `CalendarKit` which imports as a module — need SPM dependency before it compiles
- RootView has a `dismissKeyboard()` function — duplicated in TasksTabView, should be a shared utility
- Native buttons now use expanded hit shapes without visual layout changes, and the web app applies pointer cursors to semantic interactive elements.
- AppConfiguration.swift now loads from `TodosConfig.plist` first, falls back to `TaskAppConfig.plist` ✅ Fixed
- Shared AI profile settings now sync through backend `userSettings` and feed web/iOS/macOS prompts with `Context about you` and `Custom instructions`.
- macOS first-run onboarding now mirrors the iOS setup flow with skippable Gmail, calendar, and launch-page prompts persisted in `MacAppServices`.
- iOS no longer surfaces the floating custom tab bar or its onboarding/settings entry, but the implementation remains in the codebase for future reuse.
- The existing AuthSessionStore stores tokens in UserDefaults — new AuthService uses Keychain instead
- EmailService response DTOs (RawThread, GetThreadResponse) may need adjustment once tested against real backend responses ✅ Fixed — listThreads only returns IDs, now enriching via mail.get per thread (same as web app)
- Saved AI chat history previously dropped mention IDs and broke follow-up turns after reopening a conversation ✅ Fixed — persisted mention refs in saved messages with backward-compatible decoding
- Retrying an earlier assistant turn previously left later dependent turns in place and could send contradictory history on the next request ✅ Fixed — retry now truncates later turns before replaying that branch
- Spec-only `ui-spec` assistant replies previously rendered the raw fenced JSON block along with the generated UI ✅ Fixed — content is now cleared when the message only contains a UI spec
- Loading a saved chat while another AI response was streaming previously left the newly loaded chat stuck behind the old request state ✅ Fixed — history loads now cancel the active stream and clear transient errors/mentions first
- Duplicating a chat previously rebuilt messages from plain text only, dropping mentions and reply metadata, and the duplicate was not marked unsaved for autosave ✅ Fixed — duplication now preserves the full in-memory message models and leaves the duplicate as a real editable copy
- Spec-only assistant replies previously lost their retry/action row because the UI only rendered actions when `message.content` was non-empty ✅ Fixed — assistant actions now remain available when a parsed UI spec is present, and copy is disabled only when there is no text to copy
- AI chat user bubbles in the native assistant sheet previously reused the generic primary surface and could disappear into the sheet background, especially in dark mode ✅ Fixed — the chat view now uses a dedicated dynamic bubble fill with restrained contrast in both light and dark mode

---

## Last Updated: 2026-04-26
