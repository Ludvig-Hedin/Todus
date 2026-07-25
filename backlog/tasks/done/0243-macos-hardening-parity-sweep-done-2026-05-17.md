---
id: 0243
title: "macOS hardening + parity sweep (DONE) (2026-05-17)"
status: done
tags: [task-md, sprint]
files: [project.yml]
created: 2026-05-17
source: TASK.md
---

> Source context: TASK.md

## macOS hardening + parity sweep (DONE) (2026-05-17)

Comprehensive bug-fix + UX-polish + iOS → macOS parity pass on `apps/macos/TodusMac`. Full integration `xcodebuild -project apps/macos/TodusMac.xcodeproj -scheme TodusMac -destination 'platform=macOS' build` → **BUILD SUCCEEDED** (zero errors). See full per-bug detail in `CHANGELOG.md` 2026-05-17 macOS entry.

### Critical / high bug fixes (DONE)
- `DONE` **C1 Meetings duplicate top-level types** — `project.yml` exclusions held; merged secondary toolbar action into canonical `MacMeetingDetailView`.
- `DONE` **C2 Doc autosave** — flush on `onDisappear` + `onChange(docId)` + debounced title autosave + 3-state save indicator (saving / saved / failed-with-retry). Replaced placeholder doc info popover with real metadata view.
- `DONE` **C3 OAuth callback validation** — host check + queue inbound URLs until `ModelContainer` ready.
- `DONE` **C4 Push-to-talk hotkey release** — tear down `AudioInputBroker` on key-up + emit `sendActivityEnd()` end-turn frame.
- `DONE` **C5 Voice panel dual-`AVAudioEngine` crash** — `.onAppear` → `.task` with awaited sequencing.
- `DONE` **C6 Apple Reminders dedup + SwiftData `@MainActor` isolation**.
- `DONE` **C7 Task delete sync** via `MacTaskSyncService` + confirmation dialog.
- `DONE` **Email send hardening** — Bcc / `threadId` / `connectionId` / `draftId` plumbed; idempotent flush (5-min orphan window); pagination cursor race; spinner guard; stale-page drop; header sender match.
- `DONE` **Tasks resilience** — 4xx vs 5xx retry policy + max retries; word-boundary compound parser; `FolderSyncService` `syncedIds` enforcement; DST gap fix.
- `DONE` **Calendar resilience** — refresh storm dedup; per-calendar `sourceId`; multi-day overlap filter; scope-missing banner + reconnect; Toggle race fix; `accessRole` plumbing.
- `DONE` **AI / Voice race conditions** — `cancelStream` generation counter; tool exec cancellation gates; disconnect reentrancy guard; mic teardown on `.error`; serialized audio send queue with backpressure; `functionCall.id` fallback; `AudioPlayer._isPlaying` derived from buffer count; polling cross-group leak.
- `DONE` **Auth polish** — restore-flash gone; profile fetch gated; folder `createdAt` drop; settings full-shape save; voice context guard; OTP digit filter.

### iOS → macOS parity (DONE)
- `DONE` **Email compose**: attachments (NSOpenPanel chips + base64 send), per-connection signatures (new `MacSignatureStore`), live recipient validation, underline button + ⌘B / ⌘I / ⌘U shortcuts.
- `DONE` **Email thread**: verification-code chip (regex + auto-copy once), tracking-info chip (UPS / FedEx / USPS / order numbers), smart-action toolbar (Create Task / Event / Generate Reply with inline spinners), "Remind me about this…" with snooze presets + custom date picker via `MacNotificationService.scheduleEmailReminder`.
- `DONE` **Calendar**: native in-app `MacEventEditSheet` for create / edit / delete; "Open in Calendar.app" kept as context-menu fallback.
- `DONE` **Notifications**: full category registration (`TASK_REMINDER`, `EMAIL`, `EMAIL_REMINDER`, `DUE_TASKS`, `AI_RESPONSE`) + actions (`TASK_COMPLETE`, `TASK_SNOOZE`, `ARCHIVE_EMAIL`); `MacAppDelegate` implements `UNUserNotificationCenterDelegate` with foreground `willPresent` + `didReceive` routing for all types.
- `DONE` **Tasks**: recurrence (None / Daily / Weekly / Monthly / Yearly, RRULE-compatible) + checklist (live persist) + attachments (NSOpenPanel → `Application Support/TaskAttachments/{taskId}/`, relative path storage); JSON-backed accessors on `TaskRecord`.
- `DONE` **Search**: cross-entity (tasks + emails + events + people) with category chips (All / Tasks / Emails / Events / People), recent searches via `@AppStorage` with clear, debounced 60-day calendar search, keyboard nav (↑ / ↓ / ⌘1–5 / ⌘↩), people derived from email senders.
- `DONE` **Share deep link**: `todus://share?slug=...` → `MacRootView` observer → new `MacSharedConversationView` sheet (password unlock + import via `shareService.importShare`).
- `DONE` **Sidebar**: restored Meetings sidebar entry.

### UX polish (DONE)
- `DONE` ~45 items: destructive confirmations (Log Out, task delete, folder delete), toasts (send failure, event creation, restore task, openInCalendarApp failure, moveEvent completion), accessibility labels on icon-only buttons across Voice / Assistant / Calendar / Local Models, notification routing via `onOpen` closure, Home briefing → thread deep link, Search / Meetings / Local Models row affordances, save indicator 3-state, docs loading skeleton, grid / list segmented picker, outline row hover, onboarding skip de-emphasized, Q&A button color reflects state, transcript "Show all (count)", calendar all-day Copy Date, multi-day event rendering across all spanned columns, empty search → "Create task '<query>'".

### Outstanding follow-ups
- `TODO` **macOS Widget extension real-data verification pass** — wiring exists in `project.yml`; `MacWidgetUpdateManager` needs an end-to-end hydration check.
- `TODO` **`WakeWordService`** still stubbed — Picovoice Porcupine integration deferred to Phase 1.5 (tracked in macOS voice section below).
- `TODO` **`GroupChatService`** polling → WebSocket Durable Object subscription migration.
- `TODO` **`MacContentHeaderView`** top buttons still TODO real actions (accessibility labels landed).
- `TODO` **`TodusMacTests` XCTest target** — no macOS test target exists; only iOS has `TodusTests`.
