# Updated March 26 2026

1. Product strategy: one brain, three lenses
You’re not building “mail + calendar + tasks.”
You’re building a time + commitment system with an AI brain.
So:
One app.
One shared data model (people, events, threads, tasks, projects).
Assistant sits on top of everything and can touch all three.
On top of that shared core, you expose three primary “lenses”:
Mail
Calendar
Tasks
Those are navigation primitives, not separate apps.
2. High‑level structure (mobile)
Use a bottom tab bar. It’s familiar and fast.
My ideal layout:
Tab 1: Home / Inbox for life
A synthesized “Today”:
Next events
Top emails to deal with
Tasks due / overdue
One-tap AI actions: “Clear my day,” “Triage mail,” “Plan tomorrow”
Tab 2: Mail
Feels like a normal email app:
System mailboxes (Inbox, Snoozed, Sent…)
Threads
Thread view with the AI bar always visible (summarize, reply, extract tasks, propose meeting)
Tab 3: Calendar
Standard day / week view:
Tap slot → “Create event” with assistant suggesting title, location, and invitees from mail context.
Tab 4: Tasks
Focused task view:
“Today / Upcoming / Someday”
Tasks can be linked back to emails or events.
Floating or persistent Assistant button
Always visible:
Short press: open a command bar (“Email X about Y,” “Schedule with Sarah next week,” “What’s my afternoon?”).
Long press: context-aware suggestions based on current screen (email → reply; event → adjust; task → break down).
Home isn’t just an overview; it’s the “what should I do next?” surface.
Mail / Calendar / Tasks are where you go when you want control and detail.
3. Structure on Mac
On desktop, lean into panes and keyboard:
Left sidebar: primary nav
Home
Mail
Calendar
Tasks
Settings
Second column (for Mail): folders and filters.
Third column: list of items.
Fourth: detail pane (thread, event, task).
Assistant:
Global hotkey opens a command palette.
Contextual assistant panel on the right that:
Summarizes what you’re looking at.
Offers quick actions (“draft response,” “re-schedule,” “turn this into tasks”).
Keep mental model between mobile and Mac consistent:
Same four main places.
Same Assistant behavior (global + contextual).
4. Navigation principles
Here’s the logic you want:
Mode-based, not feature-based.
Users think “reply to mail,” “see my day,” “what do I need to do?”
Tabs for those modes makes sense.
Home is the control tower, not a dumping ground.
If you ship a Home tab, it must:
Be fast to scan.
Give 1–3 obvious next actions.
Be valuable multiple times per day, or it’s just in the way.
Respect habit loops.
People already open:
Mail to process communication.
Calendar to orient in time.
Tasks to remember commitments.
Don’t fight that. Augment it.
Assistant is navigation.
It should let users jump without tapping through the IA:
“Open that email from Jen about budget.”
“Show me all tasks due this week.”
“Find time with Sam and Alex next week for 30 minutes.”
Think of tabs for predictable paths, and the assistant for shortcuts and cross-cutting journeys.

The end goal is to have an ios and macos app that has these features:

Create one unified iOS app in Swift:

Big picture

You already have:

iOS Swift tasks app

ios Swift calendar app

iOS React Native + web React email app

You want: one “brain” on iOS with tasks + email + calendar (+ AI).

What the final iOS structure should be

Build a new unified iOS app in Swift (or evolve the current Swift tasks app into it):

Root nav & tabs in Swift:

Home / Today

Email

Calendar

Tasks

(Assistant button / screen)

Tasks tab: reuse your existing Swift task UI + logic.

Calendar tab:  use existing CalendarApp

Email tab: rewrite the existing web app as swift. using mostly apple ios sswift base components. not so much custom styling. make it minimal at first so we have an mvp.

Data layer:

If you already have a backend for email, mirror that architecture for tasks + calendar.

The unified app shouldn’t share data by poking into each other’s local DBs; instead, have one API / sync layer they all talk to.

Over time, move towards a shared “account” + “entities” model: messages, events, tasks, people.

How navigation should feel in the unified app

On iOS:

- Tab bar in Swift:

 ▫ Home / Today (native Swift)

 ▫ Email (native Swift)

 ▫ Calendar (native Swift)

 ▫ Tasks (native Swift)

---

Use the ai from the task app as that works. that has a chat sheet. add that to all screens. but instead of it being in the headeradd a fab in the bottom right.

---

Tab bar and FAB layout model

Overall layout

Bottom: custom split tab bar with only SF Symbols icons.

Left side: 4 primary tabs.

Right side: 1 AI button, visually separated.

Above the right side: a floating FAB-style plus button for creating items.

Design is dark mode–friendly, tight, minimal.

Tabs (left side)

Use a standard UITabBarController (or SwiftUI TabView) but styled like Craft:

4 tabs, icons only, no labels:

Home: SF Symbol e.g. ‎`house.fill`

Tasks: ‎`checkmark.circle` or ‎`checklist`

Email: ‎`envelope.fill`

Calendar: ‎`calendar`

Tabs should be horizontally tight, grouped on the left half of the bar.

Selected tab: filled/active color (e.g. accent), others: muted/secondary.

AI button (right side of tab bar)

On the right side of the same bar:

A standalone circular or rounded-rect button, not part of the 4-tab segment.

Icon only, SF Symbol like ‎`sparkles` / ‎`wand.and.stars`.

Tap: open an AI chat sheet from the bottom (full-screen or large bottom sheet):

This sheet is the assistant chat UI.

Dim the rest of the app behind it.

Visually:

Left: segmented group of 4 icons (tabs).

Right: single AI button with a little spacing gap so it feels separate.

FAB plus button (above AI button)

Above the AI button, floating:

Circular FAB centered horizontally above the AI button area, overlapping the tab bar slightly (like Craft’s plus).

Icon: ‎`plus`.

Elevated with shadow / blur to feel like a primary action.

Tap: open a “Create” input sheet from the bottom.

Create input sheet behavior

When the FAB is tapped:

Show a bottom sheet with:

A single-line text input at the top:

Placeholder: e.g. “What’s up?” or “Type anything…”

This is used for task title, event title, or email subject/body seed.

Directly below the input, a horizontal menu row to choose what to create:

Default selection: Auto.

Other options: Event, Task, Email.

Behavior:

Auto: AI decides whether this should become a task, event, or email based on the text.

Event: force create calendar event from the text.

Task: force create task from the text.

Email: open a compose flow with AI-drafted email from the text.

UI for the type menu row:

Horizontally arranged pill buttons, e.g.:

[ Auto ] [ Event ] [ Task ] [ Email ]

Only one active at a time.

Active pill: filled accent background, white text.

Others: subtle outline or muted background.

Actions:

Primary action button at bottom of sheet (e.g. “Create”):

If Auto: send text to AI, get decision + resulting object.

If Event: create event and then either dismiss or show event detail.

If Task: create task and optionally show in Tasks tab.

If Email: open email compose with suggested content.

Interaction details

FAB and AI button are always visible on main screens (Home, Tasks, Email, Calendar).

Sheet dismissals:

Tap outside sheet or swipe down to dismiss.

Navigation:

Tab changes only affect the main content view; FAB and AI button stay in place.

Visual style

Dark mode first.

Liquid glass background for tab bar (like iOS system tab bar with ‎`UIToolbarAppearance` / material). Use system default. with out blue accent for active tab icon.

Icons size: small, crisp, no labels.

Overall feel: ultra-clean, no text in the bar, just icons + one floating plus.

That’s the behavior and structure I want

---

The calendar and task pages are already created as spearate ios apps. i want to combine lal three in a swift ios app.

I have added them to the references folder:

reference/CalendarApp and reference/todo-list. Understand these also and tell me best how to add them.

Take shortcuts wherever possible. focus on getting the frontend working first with logical navigation that will actually be better than having 3 different apps.

Regarding auth:

calednar app has no auth yet. it just connects to users apple calendar.

task app has supabase auth witht magic link.

mail app has react next auth i think. or better auth. with google sign in. I want to have apple, google and email (OTP magic link) login options. idk if its best to just use the task app as base as auth works for it already. and then when the pages are live add the google and apple login so that it connects to calendar and emails on sign up. plan and design the onboarding flow also. task app shows connect to reminders after sign up. i want to keep that. so i think we should use teh task app's code as base. but use the email apps xcode project file as that has apple and google login already.

Context
You have three separate apps:

MiniTaskApp (Swift/SwiftUI) - task manager with Supabase auth, AI chat, Reminders sync
CalendarApp (UIKit + CalendarKit) - local Apple Calendar viewer/editor
Email web app (React/TS) - AI email client with Better-Auth, Cloudflare Workers backend

Goal: Merge all three into one native Swift iOS app. Unify auth under Better-Auth (the email backend). Migrate task data from Supabase to the email backend's PostgreSQL DB.
Key decisions made:

Archive React Native code, create new Swift Xcode project at apps/ios/
Bundle ID: com.ludvighedin.todus (same as current, App Store continuity)
Keep a separate "Todus Email" app running during development
Unify auth on Better-Auth (Cloudflare Workers backend) - migrate tasks to same DB
Email MVP: inbox + compose + search + swipe actions

Architecture Overview
┌──────────────────────────────────────────────────┐
│                    Todus App                      │
├──────────────────────────────────────────────────┤
│  Navigation: Custom Tab Bar (4 tabs + AI + FAB)  │
│  ┌────────┬────────┬────────┬──────────┐  [+][✦]│
│  │  Home  │ Tasks  │ Email  │ Calendar │         │
│  └────────┴────────┴────────┴──────────┘         │
├──────────────────────────────────────────────────┤
│  Features Layer (SwiftUI Views)                  │
│  • HomeView (today dashboard)                    │
│  • TasksTabView (existing MiniTaskApp views)     │
│  • EmailTabView (new, talks to existing backend) │
│  • CalendarTabView (UIKit bridge via CalendarKit)│
│  • AIChatView (global sheet from any tab)        │
│  • CreateSheet (universal create: Auto/Task/Event/Email) │
├──────────────────────────────────────────────────┤
│  Services Layer (@Observable, async/await)        │
│  • AuthService (Better-Auth: Apple + Google + OTP)│
│  • EmailAPIClient (TRPC-over-HTTP)               │
│  • TaskAPIClient (new endpoints on same backend) │
│  • CalendarService (shared EKEventStore actor)   │
│  • AIChatService (expanded multi-domain tools)   │
├──────────────────────────────────────────────────┤
│  Data Layer                                      │
│  • SwiftData: TaskRecord, FolderRecord (local cache) │
│  • In-memory: EmailThread, EmailMessage (from API)   │
│  • EventKit: EKEvent (system calendar)               │
├──────────────────────────────────────────────────┤
│  Backend: Cloudflare Workers (unified)           │
│  • Better-Auth (Apple + Google + Email OTP)      │
│  • TRPC (email + tasks + AI endpoints)           │
│  • PostgreSQL + Redis                            │
└──────────────────────────────────────────────────┘

Tech Stack
LayerTechnologyUISwiftUI (primary), UIKit bridged for CalendarKitLocal StorageSwiftData (tasks cache), EventKit (calendar), Keychain (Bearer token)NetworkingURLSession + async/awaitState@Observable + @Environment (existing MiniTaskApp pattern)ConcurrencySwift structured concurrency, actors for I/OMin iOS18.0Swift6 (strict concurrency)SPM DependenciesCalendarKit v1.1.7AuthBetter-Auth via backend (Apple Sign In, Google OAuth, email OTP)BackendCloudflare Workers + Hono + TRPC + PostgreSQL + Redis

Auth Unification Strategy
Current state:

Tasks: Supabase Auth (magic link OTP) → Supabase edge functions
Email: Better-Auth (Google/Apple/email+password) → Cloudflare Workers

Target state:

Everything: Better-Auth on Cloudflare Workers
Sign in via Apple, Google, or email OTP (all supported by Better-Auth already)
One Bearer token for all API calls (tasks, email, AI, sync)

What already exists on the backend:

apps/server/src/lib/auth.ts: Better-Auth with Apple (appBundleIdentifier: 'com.ludvighedin.todus'), Google (with Gmail scopes), Bearer plugin, JWT plugin
GET /auth/mobile-token: Converts web session → Bearer token, redirects via todus://auth-callback
POST /auth/native-link-social: Links social accounts from native app with Bearer auth
Trusted origin: todus://auth-callback already configured

Native auth flow in Swift:

Apple Sign In: Use AuthenticationServices (ASAuthorizationAppleIDProvider) to get ID token natively
Send ID token to backend POST /api/auth/sign-in/social with provider: "apple", idToken: <token>
Backend validates via Better-Auth's Apple provider, returns session
For Google Sign In: Use ASWebAuthenticationSession → backend's Google OAuth flow → redirects to todus://auth-callback?token=...
For Email OTP: Better-Auth has phoneNumber plugin; add email OTP endpoint or use existing email+password with verification
Store Bearer token in Keychain

Backend work needed for task migration:

Add task TRPC routes to apps/server/: task.list, task.create, task.update, task.delete, task.parse
Add task tables to the existing PostgreSQL schema (Drizzle): tasks, folders
Add AI chat endpoint to existing server (or reuse existing /api/ai routes)
Move Supabase edge function logic (parseTasks, syncTasks, chatAI) into Cloudflare Worker routes
The Swift app's SupabaseSyncService and SupabaseEdgeFunctionClient get replaced with a unified TodosAPIClient that talks to the same backend as email

Repo Structure
apps/ios/
  archived-rn/                         # React Native code moved here
  Todus/
    Todus.xcodeproj                    # New Swift project, same bundle ID
    Todus/
      App/
        TodosApp.swift                 # @main entry, ModelContainer setup
        AppServices.swift              # Expanded DI container
      Navigation/
        MainTabView.swift              # Custom tab bar (4 tabs + AI + FAB)
        AppTab.swift                   # Tab enum
        CreateSheet.swift              # Universal create: Auto/Event/Task/Email
      Features/
        Home/
          HomeView.swift               # Today dashboard
        Tasks/
          TasksTabView.swift           # Extracted from current RootView
          InboxView.swift              # (from MiniTaskApp)
          BoardView.swift              # (from MiniTaskApp)
          TaskTableView.swift          # (from MiniTaskApp)
          CalendarTaskView.swift       # (from MiniTaskApp)
          TaskRowView.swift            # (from MiniTaskApp)
          TaskDetailSheet.swift        # (from MiniTaskApp)
          CaptureComposer.swift        # (from MiniTaskApp)
          BoardColumnView.swift        # (from MiniTaskApp)
          BoardTaskCard.swift          # (from MiniTaskApp)
        Email/
          EmailInboxView.swift         # NEW - thread list with search
          EmailThreadView.swift        # NEW - conversation (WKWebView for HTML)
          EmailComposeView.swift       # NEW - compose sheet
          EmailConnectView.swift       # NEW - connect Gmail/Outlook prompt
          EmailRowView.swift           # NEW - swipeable thread row
        Calendar/
          CalendarContainerView.swift  # NEW - UIViewControllerRepresentable
          CalendarViewController.swift # COPIED from CalendarApp
          EKWrapper.swift              # COPIED from CalendarApp
        AI/
          AIChatView.swift             # (from MiniTaskApp, expanded)
          AIChatMessage.swift          # (from MiniTaskApp)
        Auth/
          AuthView.swift               # NEW - unified sign in (Apple/Google/Email)
          RemindersOnboardingView.swift# (from MiniTaskApp)
        Settings/
          SettingsView.swift           # (from MiniTaskApp, add email account)
        Folders/
          FolderManagementView.swift   # (from MiniTaskApp)
          MoveToFolderSheet.swift      # (from MiniTaskApp)
        Voice/
          VoiceInputButton.swift       # (from MiniTaskApp)
      Services/
        Auth/
          AuthService.swift            # NEW - Better-Auth client (replaces AuthSessionStore)
        API/
          TodosAPIClient.swift         # NEW - unified HTTP client for all backend calls
        AI/
          AIChatService.swift          # (from MiniTaskApp, expanded tools)
        Email/
          EmailService.swift           # NEW - email-specific API calls
        Calendar/
          CalendarService.swift        # NEW - shared EKEventStore actor
        Tasks/
          TaskService.swift            # NEW - task CRUD via API (replaces Supabase sync)
          TaskCaptureService.swift     # (from MiniTaskApp, rewired to new API)
        Reminders/
          AppleRemindersSyncService.swift  # (from MiniTaskApp)
          RemindersSyncState.swift         # (from MiniTaskApp)
        Parsing/
          LocalTaskParsingService.swift    # (from MiniTaskApp, offline fallback)
        AppLogger.swift                    # (from MiniTaskApp)
      Data/
        Models/
          TaskRecord.swift             # (from MiniTaskApp)
          FolderRecord.swift           # (from MiniTaskApp)
        Preview/
          PreviewData.swift            # (from MiniTaskApp)
        AppConfiguration.swift         # (from MiniTaskApp, simplified - one backend URL)
      Domain/
        TaskStatus.swift               # (from MiniTaskApp)
        AppTaskPriority.swift          # (from MiniTaskApp)
        ParseState.swift               # (from MiniTaskApp)
        SyncState.swift                # (from MiniTaskApp)
        TaskViewMode.swift             # (from MiniTaskApp)
        TaskSortOrder.swift            # (from MiniTaskApp)
        SyncModels.swift               # (from MiniTaskApp)
        AIChatConversation.swift       # (from MiniTaskApp)
        TaskParserModels.swift         # (from MiniTaskApp)
        EmailModels.swift              # NEW - thread/message/sender DTOs
        CreateItemType.swift           # NEW - Auto/Event/Task/Email enum
      DesignSystem/
        AppTheme.swift                 # (from MiniTaskApp)
        Formatters.swift               # (from MiniTaskApp)
      Resources/
        TodosConfig.plist              # Simplified: one backend URL + keys
        Assets.xcassets
        Info.plist
    TodusTests/
File count: ~48 existing from MiniTaskApp + 2 from CalendarApp + ~15 new files

Navigation & Tab Bar
Layout:
┌─────────────────────────────────────────────────┐
│                                           [+]   │  ← FAB floating
│  [🏠] [✓] [✉️] [📅]              [✦]          │  ← Tab bar
└─────────────────────────────────────────────────┘
Tabs (left side, icons only, no labels):
TabSF SymbolViewHomehouse.fillHomeViewTaskschecklistTasksTabViewEmailenvelope.fillEmailTabViewCalendarcalendarCalendarContainerView
Right side:

AI button: sparkles icon, opens AIChatView as .large sheet
FAB: plus icon, circular, floating above AI button, opens CreateSheet as .medium sheet

Styling:

.ultraThinMaterial background (liquid glass / system tab bar material)
Active tab: white/primary icon. Inactive: secondary/muted
No blue accent — white for active
Dark mode first
Custom tab bar (not system TabView) for full layout control

Implementation approach:
swiftstruct MainTabView: View {
    @State private var selectedTab: AppTab = .home
    @State private var showCreateSheet = false
    @State private var showAIChat = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Active tab content (each in its own NavigationStack)
            Group {
                switch selectedTab {
                case .home:     HomeView()
                case .tasks:    TasksTabView()
                case .email:    EmailTabView()
                case .calendar: CalendarContainerView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom tab bar overlay
            VStack(spacing: 0) {
                HStack { Spacer(); fabButton.padding(.trailing, 64) }
                customTabBar  // HStack with 4 tab icons (left) + AI button (right)
            }
        }
        .sheet(isPresented: $showCreateSheet) { CreateSheet() }
        .sheet(isPresented: $showAIChat) { AIChatView().presentationDetents([.large]) }
    }
}

Auth Flow (Onboarding)
Screen sequence:

Welcome → App icon + "Get started" button
Sign in → Three options stacked vertically:

"Continue with Apple" → native ASAuthorizationAppleIDProvider
"Continue with Google" → ASWebAuthenticationSession → backend OAuth
"Continue with Email" → email input → OTP code entry

Connect Reminders (existing RemindersOnboardingView) → Connect / Skip
Main app → Land on Home tab

Apple Sign In (native):

ASAuthorizationAppleIDProvider → user grants → returns ID token + name + email
Swift sends POST {backendURL}/api/auth/sign-in/social with { provider: "apple", idToken: token }
Better-Auth validates the ID token (already configured with appBundleIdentifier: 'com.ludvighedin.todus')
Returns session with Bearer token
Store in Keychain

Google Sign In (web flow):

Open ASWebAuthenticationSession to {backendURL}/api/auth/sign-in/social?provider=google&callbackURL=/auth/mobile-token
User completes Google OAuth in system browser
Backend redirects to /auth/mobile-token which generates Bearer token
Redirects to todus://auth-callback?token=<bearer_token>
App intercepts deep link, stores token in Keychain
Bonus: Google OAuth also grants Gmail access (scopes include gmail.modify), so email is connected automatically

Email OTP:

User enters email
Swift sends POST {backendURL}/api/auth/sign-up/email or use phone number OTP plugin adapted for email
Backend sends code via Resend
User enters 6-digit code → verified → Bearer token returned
Store in Keychain

Token storage:

Single Bearer token in Keychain (via AuthService)
Used for ALL API calls (tasks, email, AI)
No more UserDefaults for tokens

Email Tab (MVP with search + swipe)
Features:

EmailInboxView - Thread list with search bar

Pull-to-refresh
Search bar at top (searches via backend)
Each row: sender initials avatar, subject, snippet, time, unread dot
Swipe left: archive/delete
Swipe right: mark read/unread
Tap opens thread

EmailThreadView - Conversation

Messages listed chronologically
HTML bodies in WKWebView (UIViewRepresentable)
Reply button → opens compose

EmailComposeView - Sheet

To (with autocomplete from contacts), Subject, Body
Send button

EmailConnectView - Shown when no email connection

"Connect Gmail" / "Connect Outlook" buttons
For Google: uses same OAuth flow as sign-in (already grants Gmail scopes)

API calls (TRPC-over-HTTP):

POST /api/trpc/mail.list → thread list
POST /api/trpc/mail.get → single thread with messages
POST /api/trpc/mail.send → send email
POST /api/trpc/mail.modify → archive, trash, mark read
Auth: Authorization: Bearer <token> header

Data flow:

EmailService wraps TodosAPIClient for email-specific calls
Returns decoded DTOs (EmailThread, EmailMessage)
State held in @Observable service, not SwiftData (no offline cache for MVP)

Home Tab (Today Dashboard)
Sections (top to bottom in ScrollView):

Greeting - "Good morning" + date
Upcoming events - Next 3-5 events from CalendarService (EventKit)
Tasks due today - From SwiftData @Query with dueDate predicate
Unread emails - Last 5 unread threads from EmailService
Quick stats - Tasks completed today, unread count

Each section is self-contained, fetches its own data, and tap-navigates to the relevant tab.

Create Sheet (FAB)
UI:

Bottom sheet (.medium detent)
Large text input, placeholder "What's up?"
Horizontal pill selector: [Auto] [Event] [Task] [Email]
"Create" button

Behavior by type:

Auto → Send to AI, detect intent, route to Task/Event/Email
Task → TaskCaptureService.capture() → task created
Event → Parse date/title, create EKEvent via CalendarService
Email → Dismiss sheet, present EmailComposeView with text as body seed

AI Chat (Expanded)
Existing (from MiniTaskApp):

SSE streaming to backend chat endpoint
Tool calls: create_task, update_task, delete_task

Additions:

New tool calls: create_event, send_email, search_email
Context injection: today's events + recent unread emails (in addition to tasks)
Accessible from any tab via sparkles button in custom tab bar
Chat endpoint moves to unified backend (from Supabase edge function to Cloudflare Worker)

Backend Changes Required

1. Task TRPC routes (new)
Add to apps/server/src/trpc/routes/:

task.list - list user's tasks (with folder filter, sort)
task.create - create task
task.update - update task fields
task.delete - delete task
task.parse - AI-powered task parsing (title, date, priority extraction)
task.sync - batch upsert/delete for offline sync
folder.list, folder.create, folder.update, folder.delete

1. Database schema (new tables)
Add to apps/server/src/db/schema.ts (Drizzle):

tasks table: id, userId, title, description, status, priority, dueDate, folderId, reminderIdentifier, syncState, createdAt, updatedAt
folders table: id, userId, name, createdAt

1. AI chat endpoint

Move chat logic from Supabase edge function to a Cloudflare Worker route
Or add POST /api/ai/chat route that handles SSE streaming
Expand with email/calendar tool calls

1. No auth changes needed

Better-Auth already configured with Apple + Google + Bearer plugin
/auth/mobile-token and /auth/native-link-social already exist
todus://auth-callback already a trusted origin
appBundleIdentifier: 'com.ludvighedin.todus' already set for Apple Sign In

Implementation Phases
Phase 0: Project Setup (~1 day)

 Archive React Native code to apps/ios/archived-rn/
 Create new Xcode project Todus in apps/ios/Todus/
 Set bundle ID to com.ludvighedin.todus, configure signing (team XDBG7P4V96)
 Copy all MiniTaskApp source files into new structure
 Add CalendarKit SPM dependency
 Copy CalendarViewController.swift + EKWrapper.swift
 Verify project builds and existing task features work
Milestone: Task app runs in new Xcode project

Phase 1: Backend — Task Migration + Schema (~2-3 days)

 Add tasks and folders tables to Drizzle schema
 Add task TRPC routes (list, create, update, delete, sync)
 Add folder TRPC routes
 Migrate AI chat endpoint from Supabase edge function to Cloudflare Worker
 Test all new endpoints via curl/Postman
Milestone: Backend serves tasks + email + AI from one server with one auth

Phase 2: Unified Auth in Swift (~2 days)

 Build AuthService (replaces AuthSessionStore) — Better-Auth client
 Implement Apple Sign In (ASAuthorizationAppleIDProvider → backend)
 Implement Google Sign In (ASWebAuthenticationSession → backend OAuth)
 Implement email OTP flow
 Build AuthView (new onboarding screen with 3 sign-in options)
 Store Bearer token in Keychain
 Build TodosAPIClient (base HTTP client with Bearer auth)
 Rewire TaskCaptureService + sync to use new backend (replace Supabase calls)
 Keep RemindersOnboardingView as post-auth step
Milestone: Sign in via Apple/Google/Email, tasks sync to new backend

Phase 3: Navigation Shell + Calendar (~2 days)

 Build MainTabView with custom tab bar (4 icons + AI + FAB)
 Build AppTab enum
 Extract current RootView into TasksTabView
 Create CalendarContainerView (UIViewControllerRepresentable wrapping CalendarViewController)
 Create CalendarService actor (shared EKEventStore)
 Build skeleton HomeView (tasks due today + upcoming events)
 Move AI chat + Settings sheets to MainTabView level
 Build CreateSheet with type selector (Task + Event working)
Milestone: 4 tabs working. Tasks fully functional. Calendar shows events. Home shows today.

Phase 4: Email Tab (~4-5 days)

 Build EmailModels.swift (thread, message, sender DTOs matching backend TRPC output)
 Build EmailService (wraps TodosAPIClient for email calls)
 Build EmailConnectView (for users who signed in with Apple/email but need to connect Gmail)
 Build EmailRowView (swipeable row with sender avatar, subject, snippet, time)
 Build EmailInboxView (thread list + search bar + pull-to-refresh + swipe actions)
 Build EmailThreadView (message list + WKWebView for HTML bodies)
 Build EmailComposeView (To, Subject, Body, Send)
 Add email section to HomeView
 Wire "Email" type in CreateSheet
Milestone: Full email MVP — connect, inbox, read, search, swipe, compose.

Phase 5: AI Expansion + Polish (~2 days)

 Expand AIChatService with calendar/email tool calls
 Wire "Auto" mode in CreateSheet (AI intent detection)
 HomeView: loading states, empty states, pull-to-refresh
 Dark mode refinements across all new views
 Tab bar: liquid glass material
 Settings: email account management (connect/disconnect)
Milestone: Production-quality MVP

Phase 6: TestFlight (~1 day)

 Final build, signing, provisioning
 Update app icon
 Archive and submit to TestFlight
Milestone: Testable build distributed

Key Reusable Code
WhatSourceStrategyAuth patternsreference/todo-list/MiniTaskApp/Services/Auth/AuthSessionStore.swiftRewrite for Better-Auth, keep @Observable patternDI containerreference/todo-list/MiniTaskApp/App/AppServices.swiftCopy + expand with new servicesAI chat UI + servicereference/todo-list/MiniTaskApp/Features/AI/ + Services/AI/Copy, expand tool callsTask viewsreference/todo-list/MiniTaskApp/Features/Inbox/*, Board/*, Table/*Copy as-isTask modelsreference/todo-list/MiniTaskApp/Data/Models/*, Domain/*Copy as-isCalendar VCreference/CalendarApp/Calendar/CalendarViewController.swiftCopy, wrap in UIViewControllerRepresentableEKWrapperreference/CalendarApp/Calendar/EKWrapper.swiftCopy as-isThemereference/todo-list/MiniTaskApp/DesignSystem/AppTheme.swiftCopy as-isReminders syncreference/todo-list/MiniTaskApp/Services/Reminders/*Copy as-isTask capturereference/todo-list/MiniTaskApp/Services/Capture/*Copy, rewire APIBackend authapps/server/src/lib/auth.tsAlready configured, no changesMobile tokenapps/server/src/main.ts (/auth/mobile-token)Already exists, use as-isBackend DBapps/server/src/db/Add task/folder tables to existing schema

Verification Plan

Build: Project compiles with no errors on iOS 18 simulator
Auth: Can sign in with Apple, Google, and email OTP; Bearer token stored in Keychain
Tasks tab: All existing features work (create, edit, delete, board, calendar view, search, folders, reminders sync) — now syncing to unified backend
Calendar tab: Shows system calendar events, can create/edit via CalendarKit
Email tab: Connect Gmail, view inbox, search, swipe to archive, open thread, compose and send
Home tab: Shows upcoming events, due tasks, unread emails
Create sheet: Can create tasks, events, and open email compose via FAB
AI chat: Streaming works, task + email + calendar tool calls work
Navigation: Tab switching smooth, sheets present/dismiss correctly, FAB + AI always visible
Signing: App runs on physical device with correct bundle ID and provisioning
