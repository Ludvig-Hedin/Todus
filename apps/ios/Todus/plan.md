# Todus — Build Plan

## Build Order
1. **iOS app** — primary target, ships first
2. **Backend changes** — run in parallel with iOS frontend work
3. **macOS app** — after iOS is stable, share code via multi-platform target

---

## Phase 0: Project Setup ✅
**Goal:** New Swift project with all existing code copied in.

- [x] Archive React Native code to `archived-rn/`
- [x] Create new `apps/ios/Todus/` directory structure
- [x] Copy all MiniTaskApp Swift files (48 files)
- [x] Copy CalendarApp files (CalendarViewController, EKWrapper)
- [x] Rename @main struct to TodosApp
- [x] Create AppTab, CreateItemType, EmailModels domain types
- [x] Create MainTabView with custom tab bar
- [x] Create TasksTabView (extracted from RootView)
- [x] Create CalendarContainerView (UIViewControllerRepresentable)
- [x] Create CalendarService actor
- [x] Create HomeView skeleton
- [x] Create CreateSheet
- [ ] Set up Xcode project (xcodeproj) — **requires Xcode**
- [ ] Add CalendarKit SPM dependency
- [ ] Verify build compiles

**Milestone:** Task app runs in new project with tab navigation.

---

## Phase 1: Backend — Task Migration (~2-3 days)
**Goal:** One backend serves tasks + email + AI with unified auth.

### Database
- [ ] Add `tasks` table to Drizzle schema (id, userId, title, description, status, priority, dueDate, folderId, reminderIdentifier, createdAt, updatedAt)
- [ ] Add `folders` table (id, userId, name, createdAt)
- [ ] Run migration on PostgreSQL

### TRPC Routes
- [ ] `task.list` — list tasks with folder filter + sort
- [ ] `task.create` — create single task
- [ ] `task.update` — update task fields
- [ ] `task.delete` — delete task
- [ ] `task.sync` — batch upsert/delete for offline sync
- [ ] `task.parse` — AI-powered text parsing (title, date, priority)
- [ ] `folder.list` — list user's folders
- [ ] `folder.create` — create folder
- [ ] `folder.update` — rename folder
- [ ] `folder.delete` — delete folder (cascade tasks)

### AI Chat
- [ ] Add `POST /api/ai/chat` SSE streaming endpoint
- [ ] Port system prompt + tool call logic from Supabase edge function
- [ ] Add email/calendar tool calls

**Milestone:** `curl` can create/list/update tasks via the same backend that serves email.

---

## Phase 2: Unified Auth in Swift (~2 days)
**Goal:** Sign in via Apple, Google, or email OTP. One token for everything.

### AuthService (Swift)
- [ ] Build `AuthService` (@Observable, replaces AuthSessionStore)
- [ ] Implement Apple Sign In (ASAuthorizationAppleIDProvider → backend `POST /api/auth/sign-in/social`)
- [ ] Implement Google Sign In (ASWebAuthenticationSession → backend OAuth → `todus://auth-callback`)
- [ ] Implement email OTP (send code → verify → Bearer token)
- [ ] Store Bearer token in Keychain (not UserDefaults)
- [ ] Handle deep link callback (`todus://auth-callback?token=...`)
- [ ] Handle token refresh / expiry

### AuthView (Swift)
- [ ] Build new onboarding screen with 3 sign-in options
- [ ] Keep RemindersOnboardingView as post-auth step
- [ ] Update RootView to use AuthService instead of AuthSessionStore

### TodosAPIClient (Swift)
- [ ] Build base HTTP client (URLSession + async/await)
- [ ] Auto-attach `Authorization: Bearer <token>` header
- [ ] TRPC request helper (`POST /api/trpc/{procedure}` with JSON body)
- [ ] Error handling (401 → sign out, network errors → retry)

### Rewire Task Sync
- [ ] Replace SupabaseEdgeFunctionClient calls with TodosAPIClient
- [ ] Replace SupabaseSyncService with new TaskService
- [x] Update AIChatService to use new backend endpoint
- [x] Add per-message AI retry action and stabilize copy button layout

**Milestone:** User signs in with Apple/Google/Email, tasks sync to unified backend.

---

## Phase 3: Navigation Shell + Calendar (~2 days)
**Goal:** Four working tabs with proper navigation.

- [ ] Wire MainTabView into RootView (replace old single-view layout)
- [ ] Ensure TasksTabView works with all existing views
- [ ] Ensure CalendarContainerView shows events (test EventKit permission)
- [ ] Wire HomeView with live data (events + tasks)
- [ ] Wire CreateSheet task creation
- [ ] Move AI chat and Settings sheets to MainTabView level
- [ ] Test tab switching, sheet present/dismiss
- [ ] Add bottom padding to tab content for custom tab bar clearance
- [ ] Add CalendarKit SPM dependency and verify CalendarViewController builds

**Milestone:** 4 working tabs. Tasks fully functional. Calendar shows events.

---

## Phase 4: Email Tab (~4-5 days)
**Goal:** Connect Gmail, view inbox, read threads, search, swipe, compose.

### Models & Service
- [ ] Finalize EmailModels.swift (match actual TRPC response shapes)
- [ ] Build EmailService (@Observable, wraps TodosAPIClient for email calls)
- [ ] Implement thread list fetching (pagination, search)
- [ ] Implement thread detail fetching (messages with HTML bodies)
- [ ] Implement send email
- [ ] Implement modify (archive, trash, mark read/unread)

### Views
- [ ] Build EmailConnectView (OAuth to connect Gmail/Outlook)
- [ ] Build EmailRowView (sender avatar initials, subject, snippet, time, unread dot)
- [ ] Build EmailInboxView (list + search bar + pull-to-refresh)
- [ ] Add swipe actions to EmailRowView (archive, delete, mark read)
- [ ] Build EmailThreadView (message list)
- [ ] Build HTMLEmailView (WKWebView wrapper for HTML email bodies)
- [ ] Build EmailComposeView (To, Subject, Body, Send button)
- [ ] Add email section to HomeView
- [ ] Wire "Email" type in CreateSheet

**Milestone:** Full email MVP.

---

## Phase 5: AI Expansion + Polish (~2 days)
**Goal:** AI assistant works across all domains. UI is production-quality.

- [ ] Add `create_event` tool call to AIChatService
- [ ] Add `send_email`, `search_email` tool calls
- [ ] Inject today's events + recent emails into AI context
- [ ] Wire "Auto" mode in CreateSheet (AI decides task/event/email)
- [ ] HomeView: loading skeletons, empty states, pull-to-refresh
- [ ] Tab bar: verify liquid glass material looks correct
- [ ] Dark mode audit across all new views
- [ ] Settings: add email account management section
- [ ] Haptic feedback on key interactions

**Milestone:** Production-quality MVP.

---

## Phase 6: TestFlight (~1 day)
**Goal:** Ship a testable build.

- [ ] Configure code signing (team XDBG7P4V96, bundle ID com.ludvighedin.todus)
- [ ] Update app icon
- [ ] Archive build
- [ ] Submit to TestFlight
- [ ] Test on physical device

**Milestone:** Distributed TestFlight build.

---

## Phase 7: macOS App (Future)
**Goal:** Share Swift codebase with a macOS target.

- [ ] Add macOS destination to Xcode project
- [ ] Adapt navigation for sidebar-based layout (NavigationSplitView)
- [ ] Adapt tab bar for macOS toolbar
- [ ] Conditional compilation for platform-specific code (#if os(macOS))
- [ ] CalendarKit may need macOS adaptation or replacement
- [ ] Test and polish macOS-specific interactions

**Milestone:** macOS app on TestFlight.

---

## Key Milestones Timeline

| Phase | Milestone | Target |
|-------|-----------|--------|
| 0 | Project compiles | Day 1 |
| 1 | Backend serves tasks | Day 3-4 |
| 2 | Unified auth working | Day 5-6 |
| 3 | 4 tabs with navigation | Day 7-8 |
| 4 | Email MVP complete | Day 12-13 |
| 5 | AI + polish | Day 14-15 |
| 6 | TestFlight | Day 16 |
| 7 | macOS | TBD |
