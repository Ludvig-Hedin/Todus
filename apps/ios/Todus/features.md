# Todus — Feature List

## Overview
Todus is a unified AI productivity app combining email, tasks, calendar, and an AI assistant into one native iOS (and later macOS) app.

---

## Email

### P0 — Must Have (MVP)
- [ ] **Inbox view** — List of email threads with sender, subject, snippet, time, unread indicator
- [ ] **Thread view** — Read full email conversations with HTML rendering
- [ ] **Compose** — Create and send new emails (To, Subject, Body)
- [ ] **Reply** — Reply to emails from thread view
- [ ] **Gmail connect** — OAuth flow to connect Gmail account
- [ ] **Search** — Search inbox by keyword (server-side)
- [ ] **Swipe actions** — Swipe left to archive/delete, swipe right to mark read/unread
- [ ] **Pull to refresh** — Refresh inbox from server
- [ ] **Unread badge** — Show unread count on email tab icon

### P1 — Important
- [ ] **Multiple accounts** — Connect multiple email accounts
- [ ] **Outlook connect** — OAuth for Microsoft Outlook
- [ ] **Labels/folders** — View emails by label/folder
- [ ] **AI email summaries** — One-line AI summary per thread
- [ ] **Smart replies** — AI-generated reply suggestions
- [ ] **AI compose** — Write email from a prompt ("Draft a follow-up to John about the meeting")
- [ ] **Attachments** — View and download email attachments
- [ ] **Inline images** — Render inline images in HTML emails
- [ ] **CC/BCC** — CC and BCC fields in compose
- [ ] **Draft saving** — Auto-save drafts

### P2 — Nice to Have
- [ ] **People view** — Group emails by sender/contact
- [ ] **Categories** — Gmail-style categories (Primary, Social, Promotions, Updates)
- [ ] **Snooze** — Snooze emails to reappear later
- [ ] **Scheduled send** — Schedule emails to send later
- [ ] **Email templates** — Save and reuse email templates
- [ ] **Signature** — Custom email signatures
- [ ] **Notifications** — Push notifications for new emails
- [ ] **Thread notes** — Add private notes to email threads
- [ ] **Keyboard shortcuts** — iPad external keyboard shortcuts

---

## Tasks

### P0 — Must Have (MVP)
- [x] **Task creation** — Quick capture text input
- [x] **Task list** — Scrollable list with checkbox, title, priority, folder
- [x] **Task completion** — Toggle checkbox to mark done
- [x] **Task editing** — Edit title, description, priority, due date, folder
- [x] **Folders** — Organize tasks into folders
- [x] **Board view** — Kanban-style columns (Todo, Doing, Done)
- [x] **Table view** — Spreadsheet-style task list
- [x] **Calendar view** — Tasks plotted on a calendar by due date
- [x] **Search** — Search tasks by title
- [x] **Sort** — Sort by newest, oldest, priority
- [x] **Apple Reminders sync** — Two-way sync with Apple Reminders

### P1 — Important
- [x] **AI task parsing** — Auto-extract title, date, priority from raw text
- [x] **AI chat task creation** — Create tasks from the AI assistant
- [ ] **Subtasks** — Nested tasks within a parent task
- [ ] **Recurring tasks** — Tasks that repeat on a schedule
- [ ] **Tags** — Label tasks with custom tags
- [ ] **Task sharing** — Share tasks with others

### P2 — Nice to Have
- [ ] **Drag and drop** — Reorder tasks and move between folders
- [ ] **Time tracking** — Track time spent on tasks
- [ ] **Task dependencies** — Link tasks that depend on each other
- [ ] **Batch actions** — Select multiple tasks for bulk operations

---

## Calendar

### P0 — Must Have (MVP)
- [x] **Day view** — Full day timeline with events (via CalendarKit)
- [x] **Event display** — Show all Apple Calendar events with color coding
- [x] **Event detail** — Tap to view event details (native EKEventViewController)
- [x] **Event editing** — Long-press to create/edit events (native EKEventEditViewController)
- [x] **Calendar permissions** — Request and handle EventKit access

### P1 — Important
- [ ] **Week view** — 7-day overview
- [ ] **Month view** — Monthly calendar with event dots
- [ ] **Create from text** — "Meeting tomorrow at 3pm" → creates event
- [ ] **Calendar selection** — Filter by specific calendars
- [ ] **Event search** — Search events by title

### P2 — Nice to Have
- [ ] **Travel time** — Show travel time between events
- [ ] **Availability sharing** — Generate "free/busy" times
- [ ] **Meeting scheduling** — AI-powered meeting time suggestions
- [ ] **Video call links** — Quick join for Zoom/Meet/Teams links in events

---

## AI Assistant

### P0 — Must Have (MVP)
- [x] **Chat interface** — Full-screen chat sheet with streaming responses
- [x] **Task tools** — AI can create, update, delete tasks
- [x] **Conversation history** — Save and load past conversations
- [x] **Model selection** — Choose between different AI models

### P1 — Important
- [ ] **Email tools** — AI can compose, send, search emails
- [ ] **Calendar tools** — AI can create events, check availability
- [ ] **Cross-domain context** — AI sees tasks + events + emails for holistic answers
- [ ] **Auto-classify** — AI auto-routes "Create" sheet input (Auto mode)
- [ ] **Voice input** — Speak to the AI assistant

### P2 — Nice to Have
- [ ] **Proactive suggestions** — AI suggests actions based on inbox/calendar
- [ ] **Meeting prep** — AI summarizes relevant emails before a meeting
- [ ] **Daily briefing** — Morning summary of tasks, events, and important emails
- [ ] **Smart scheduling** — "Find me a 30-min slot this week" → suggests times

---

## Home / Today

### P0 — Must Have (MVP)
- [ ] **Greeting** — Time-appropriate greeting with current date
- [ ] **Today's events** — Next 5 events from Apple Calendar
- [ ] **Due tasks** — Tasks due today from SwiftData
- [ ] **Recent emails** — Last 5 unread threads (after email is connected)

### P1 — Important
- [ ] **Quick stats** — Tasks completed today, unread email count
- [ ] **Tap to navigate** — Tapping items navigates to the relevant tab
- [ ] **Pull to refresh** — Refresh all sections

### P2 — Nice to Have
- [ ] **Widgets** — iOS home screen widgets for today view
- [ ] **Focus filters** — Different home views per Focus mode

---

## Navigation & Global

### P0 — Must Have (MVP)
- [ ] **Custom tab bar** — 4 tabs (icons only) + AI button + floating FAB
- [ ] **FAB create sheet** — Universal create with type selector (Auto/Task/Event/Email)
- [ ] **AI chat sheet** — Accessible from any tab via sparkles button
- [ ] **Settings** — Appearance, accounts, reminders toggle

### P1 — Important
- [ ] **Deep links** — `todus://` URL scheme for auth callbacks and navigation
- [ ] **Haptic feedback** — Subtle haptics on tab switch, create, complete
- [ ] **iPad support** — Adaptive layout with sidebar on iPad

### P2 — Nice to Have
- [ ] **macOS app** — Native macOS app sharing the same codebase
- [ ] **Spotlight integration** — Search tasks/emails from Spotlight
- [ ] **Siri shortcuts** — "Hey Siri, add a task" integration

---

## Auth & Accounts

### P0 — Must Have (MVP)
- [ ] **Apple Sign In** — Native ASAuthorizationAppleIDProvider
- [ ] **Google Sign In** — ASWebAuthenticationSession → backend OAuth
- [ ] **Email OTP** — 6-digit code via email (Better-Auth)
- [ ] **Bearer token** — Stored in Keychain, used for all API calls
- [ ] **Onboarding flow** — Welcome → Sign in → Connect Reminders → Main app

### P1 — Important
- [ ] **Account management** — View/disconnect connected accounts in Settings
- [ ] **Session refresh** — Auto-refresh expired tokens
- [ ] **Sign out** — Clear all local data and tokens

### P2 — Nice to Have
- [ ] **Biometric lock** — Face ID / Touch ID to unlock app
- [ ] **Multiple profiles** — Switch between work/personal accounts
