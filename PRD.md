# Todus — Product Requirements Document

> Last updated: March 27, 2026

---

## 1. Product Vision

**Todus** is a unified time and commitment system with an AI brain.

It is not "mail + calendar + tasks." It is one app with one shared data model (people, events, threads, tasks) and an AI assistant that sits on top of everything.

**Target user:** Professionals who use email, calendar, and task management daily and want one app that connects all three — reducing context-switching and surfacing what matters.

**Core value proposition:** Replace three apps with one. The AI layer connects information across email, calendar, and tasks so users spend less time organizing and more time executing.

---

## 2. Information Architecture

Four primary "lenses" expose the shared data model. These are navigation modes, not separate apps:

| Tab | Purpose | Key content |
|-----|---------|------------|
| **Home** | "What should I do next?" | Today's events, due tasks, recent emails, AI actions |
| **Tasks** | Remember commitments | List/board/table/calendar views, folders, Reminders sync |
| **Email** | Process communication | Gmail inbox, threads, compose, search, swipe actions |
| **Calendar** | Orient in time | Day/week view via system calendar (EventKit) |

**AI Assistant** — Always accessible via the sparkles button in the tab bar. Acts as both a chat interface and a navigation shortcut ("Open that email from Jen about budget").

**FAB (Create button)** — Floating plus button above the tab bar. Opens a universal create sheet with type selector: Auto (AI decides), Task, Event, Email.

### Mobile (iOS)
- Bottom tab bar: 4 nav tabs (left) + AI button (right) + floating FAB
- Custom glass-pill tab bar, icons only, no labels
- Dark mode first, ultra-clean

### Desktop (macOS)
- Left sidebar: Home, Mail, Calendar, Tasks, Settings
- Multi-column layout: folders → list → detail pane
- Global hotkey command palette for AI

---

## 3. User Flows

### 3.1 First Launch (New User)
```
App launch
  → Welcome screen (app icon + "Get started")
  → Sign in screen:
      • "Continue with Apple" (native)
      • "Continue with Google" (web OAuth — also connects Gmail)
      • "Continue with Email" (OTP code)
  → Connect Apple Reminders (optional, skip available)
  → Connect Gmail (if signed in with Apple/Email — optional, skip available)
  → Land on Home tab
```

**Key behaviors:**
- Google sign-in automatically connects Gmail (OAuth scopes include `gmail.modify` for full read/write/send access, plus `gmail.readonly` and `gmail.send` as narrower fallbacks)
- Apple/Email sign-in requires a separate Gmail connection step
- Reminders connection is always optional but prompted first
- The app is usable immediately after sign-in — email/calendar are additive

### 3.2 Return Visit
```
App launch
  → Check Keychain for Bearer token
  → If token exists and valid: restore to last-used tab (persisted via SceneStorage)
  → If token expired: attempt silent refresh (GET /api/auth/get-session)
    → If refresh succeeds: continue normally
    → If refresh fails: show "Session expired" banner with "Sign in again" button
      (do NOT force logout — local tasks and calendar remain accessible)
```

### 3.3 Network Loss Mid-Use
| Feature | Behavior when offline |
|---------|----------------------|
| Tasks | Fully functional — SwiftData is local-first. Changes queue for sync when reconnected. |
| Calendar | Fully functional — EventKit is local. |
| Email | Read-only cached threads. Loading/sending shows "No connection" banner. |
| AI Chat | Shows "Can't reach the assistant. Check your connection." with retry button. |
| Home | Cached data still visible. Pull-to-refresh shows offline banner. |

A subtle, non-blocking "Offline" banner appears at the top of the screen when network is unavailable.

### 3.4 Token Expiration During Use
- Any API call returning 401 triggers: (1) one silent refresh attempt, (2) if that fails, set `isSessionExpired` flag
- A top banner appears: "Session expired — Sign in again"
- Tapping the banner presents the auth screen as a sheet (not a full replacement)
- Local-first features (tasks, calendar) continue working
- Email and AI are disabled until re-authenticated

### 3.5 No Email Connected
| Tab | What user sees | Prompt |
|-----|---------------|--------|
| Home | Email section shows "Connect Gmail on the Email tab" (tappable) | Tap navigates to Email tab |
| Email | Full-screen EmailConnectView with "Connect Gmail" button | Starts Google OAuth flow |
| Tasks | Unaffected — tasks work independently | — |
| Calendar | Unaffected — calendar works independently | — |
| AI | Can still manage tasks/calendar. Email-related commands return "Connect Gmail first." | Suggestion to connect |

---

## 4. Screen Specifications

### 4.1 Home Tab
**Purpose:** "What should I do next?" — a daily control tower.

**Content (top to bottom):**
1. Greeting ("Good morning") + current date
2. Today's Events — next 3-5 events from system calendar
3. Due Today — tasks with today's due date
4. Recent Emails — last 5 unread threads (if connected)

**Each section:** Self-contained with its own empty state. Tap navigates to the relevant tab. "+" button creates in that category.

**Design rules:**
- Must be fast to scan (< 2 seconds to understand your day)
- Give 1-3 obvious next actions
- Valuable on every open, or it's in the way

### 4.2 Email Tab
**Purpose:** Gmail inbox that feels native.

**Content:**
- Thread list with search bar (searches via backend)
- Pull-to-refresh
- Each row: sender avatar/initials, subject, snippet, timestamp, unread indicator
- Swipe left: archive/delete
- Swipe right: mark read/unread
- Tap: opens full thread view with chronological messages

**Thread view:** Messages with HTML rendering. Reply button opens compose.

**Compose:** To field (with autocomplete), Subject, Body, Send button.

### 4.3 Calendar Tab
**Purpose:** Orient in time — standard day/week view.

**Content:** CalendarKit day view powered by EventKit (system calendar).

**Tap empty slot:** Create event (with AI suggesting title, location, invitees from mail context — future).

### 4.4 Tasks Tab
**Purpose:** Remember and manage commitments.

**View modes:** List (default), Board (kanban by status), Table (spreadsheet), Calendar (by due date).

**Content:** Folder strip at top, view mode picker, search. Capture composer always visible at bottom.

**Task fields:** Title, description, status (todo/doing/done), priority (none/low/medium/high), due date, folder, linked email thread (tap opens the thread in Email tab), linked calendar event (tap opens the event in Calendar tab). These links are stored as `emailThreadId` and `eventId` on the task record (see Section 9.1).

### 4.5 AI Chat
**Purpose:** Natural language control over all three domains.

**Content:** Streaming chat with markdown rendering. Tool calls for: create/update/delete tasks, create events, send/search email.

**Context injection:** System prompt includes today's events, due tasks, unread email count, and current tab context.

---

## 5. Empty & Error States

| Screen | Trigger | What user sees | Action |
|--------|---------|---------------|--------|
| **Home — Events** | Calendar permission denied | "Allow calendar access" card | "Open Settings" button |
| **Home — Events** | No events today | "No events today" card | Tap → Calendar tab |
| **Home — Tasks** | No tasks due | "No tasks due today" card | Tap → Tasks tab |
| **Home — Email** | Not connected | "Connect Gmail on the Email tab" card | Tap → Email tab |
| **Home — All empty** | No data anywhere | Single "Get started" card with setup links | Connect services |
| **Email** | Not connected | Full-screen EmailConnectView | "Connect Gmail" button |
| **Email** | Connected, empty inbox | "No emails" with tray icon | Pull to refresh |
| **Email** | Network error | "Failed to load emails" | Retry button |
| **Calendar** | Permission denied | "Calendar access required" view | "Open Settings" button |
| **Calendar** | Permission granted, empty | CalendarKit empty day (native) | Tap to create event |
| **Tasks** | No tasks created | Empty list with capture composer visible | Type to create |
| **AI** | Backend unreachable | "Can't reach the assistant" centered card | Retry button |
| **AI** | Not authenticated | "Sign in to use the AI assistant" | Sign in button |

---

## 6. Notifications

### 6.1 Events That Trigger Notifications
| Event | Type | Default timing |
|-------|------|---------------|
| Task due date approaching | Local | 1 hour before due date |
| Calendar event starting | System (EventKit handles) | 15 minutes before (iOS default) |
| AI task extraction complete | Local (future) | Immediately after extraction |
| New email from starred sender | Push (future) | Real-time |

### 6.2 Notification Actions
| Category | Actions |
|----------|---------|
| Task reminder | **Complete** (marks task done) · **Snooze 1h** (reschedules +1 hour) |
| Email notification (future) | **Mark Read** · **Archive** |
| Calendar reminder | Handled by iOS system — **Snooze 15m** |

### 6.3 Grouping Strategy
- Group by category: Tasks, Email, Calendar
- Thread identifier = category string (e.g., `todus.tasks`, `todus.email`)
- Collapsed summary: "3 tasks due today"

### 6.4 Implementation Note
The initial implementation uses `UNUserNotificationCenter` local notifications only. No push notification server needed. Push notifications deferred until backend infrastructure is ready.

---

## 7. AI Interaction Model

### 7.1 Access Points
- **Sparkles button** in tab bar (always visible): Opens AI chat sheet
- **Quick action chips**: Shown above input when chat is empty (context-aware per tab)
- **Create sheet "Auto" mode**: AI determines intent and routes to task/event/email

### 7.2 Chat Sheet Behavior
- **Single tap** on sparkles: Opens chat sheet at 50% height
- **Drag up** or scroll: Expands to full screen
- Sheet stays interactive with content behind it at 50% height (`.presentationBackgroundInteraction`)

### 7.3 Context-Aware Suggestions
When the chat opens with no messages, show quick action chips based on the current tab:

| Current tab | Suggested chips |
|------------|----------------|
| Home | "Triage my day" · "What's next?" |
| Email | "Summarize this thread" · "Draft a reply" |
| Tasks | "What's overdue?" · "Break this down" |
| Calendar | "Find free time" · "Schedule a meeting" |

Tapping a chip sends it as a user message.

### 7.4 Context Injection
The AI system prompt automatically includes:
- Current tab name
- Today's event count + next event title
- Due/overdue task count + current folder
- Unread email count
- AI tone preference (Professional / Casual / Concise)

---

## 8. Settings Screen Spec

### 8.1 Account
- Profile avatar (Google image or initial fallback), name, email
- **Sign out** button with confirmation dialog
- **Delete account** button with double confirmation (dialog → typed "DELETE" alert)
  - Cascading delete: user data, tasks, folders, connections, sessions
  - Clears Keychain and local data, returns to auth screen
  - **Does NOT delete:** Apple Reminders (managed by iOS), calendar events (managed by EventKit), or any data in external services (Gmail messages, etc.)

### 8.2 Connected Services
- **Gmail**: Status indicator (Connected / Not connected). If connected: "Disconnect" button. If not: initiates Google OAuth.
- **Apple Calendar**: Status from EventKit authorization. If denied: "Connect" button → requests access.
- **Apple Reminders**: NavigationLink to RemindersSetupView. Shows sync direction (two-way, to Reminders, from Reminders).

### 8.3 Appearance
- Theme picker: System / Light / Dark (with visual preview swatches)

### 8.4 Email
- Swipe gestures toggle
- Email signature (toggle + text field)
- Thread grouping toggle

### 8.5 AI Assistant
- "Read my tasks" toggle (AI can see task list)
- "Create & edit tasks" toggle (AI can mutate tasks)
- **Tone** picker: Professional / Casual / Concise (injected into AI system prompt)

### 8.6 Preferences
- Default task view mode (List / Board / Table / Calendar)
- Manage folders (NavigationLink)
- Developer mode toggle

### 8.7 Notifications
- "Task due date reminders" toggle (controls local notification scheduling)
- "Calendar event reminders" toggle
- "System Settings" link (opens iOS notification settings)

### 8.8 Privacy & Security
- App Permissions link (opens iOS settings)
- Data sync indicator ("End-to-end")

### 8.9 About
- Version number, build number

---

## 9. Database Schema Revisions

### 9.1 Task Table Additions
Add to the existing `task` table:
- **`emailThreadId`** (text, nullable): Links a task to the Gmail thread it was extracted from. Stored as the Gmail thread ID string. No formal foreign key — thread IDs come from Gmail, not our database. If the referenced thread is deleted or the Gmail connection is removed, the field becomes a dangling reference — the UI should handle this gracefully (hide the link or show "Thread unavailable").
- **`eventId`** (text, nullable): Links a task to a calendar event. Stored as the EKEvent `eventIdentifier` string. No formal foreign key — managed by EventKit. If the referenced event is deleted from the calendar, the field becomes a dangling reference — the UI should handle this gracefully (hide the link or show "Event not found").

These enable the PRD goal: "Tasks can be linked back to emails or events."

### 9.2 People Table
**Decision: Not now.** Contacts/senders are currently derived from email thread metadata (`EmailThread.from` contains name + email). A formal `people` table adds migration complexity for no immediate user-facing value.

**Revisit when:** Building a "People" view, implementing cross-entity contact resolution, or needing contact search across tasks and email.

---

## 10. Platform Differences

| Feature | iOS | macOS |
|---------|-----|-------|
| Navigation | Bottom tab bar (4 tabs + AI + FAB) | Left sidebar + multi-column panes |
| AI access | Sparkles button in tab bar | Global hotkey command palette |
| Create | Floating FAB → bottom sheet | Keyboard shortcut → modal |
| Calendar | CalendarKit (UIKit bridge) | System calendar integration |
| Offline | SwiftData + EventKit local | Web app requires connection (macOS app is an Electron WebView wrapping the web app, so it also requires connection) |
