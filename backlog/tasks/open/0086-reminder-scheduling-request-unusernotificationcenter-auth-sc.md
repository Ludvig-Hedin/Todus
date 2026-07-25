---
id: 0086
title: "Reminder scheduling — Request UNUserNotificationCenter auth; schedule a UNCalendarNotificationTrigger on task"
status: open
priority: P2
tags: [macos, qa, code-review-backlog]
files: []
created: 2026-05-28
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-28 — macOS QA deferred features (found, not yet fixed) → Deferred — net-new feature

| Area | Where | Severity | Problem | Suggested fix |
|------|-------|----------|---------|---------------|
| Reminder scheduling | `MacNotificationService.scheduleTaskReminder` / `scheduleDueTodayDigest` (never called); Settings toggles `taskRemindersEnabled` / `calendarRemindersEnabled` | ⚠️ high (dead control) | The reminder toggles persist + sync but schedule nothing — no local notification ever fires for a due task. Net-new on iOS too. | Request `UNUserNotificationCenter` auth; schedule a `UNCalendarNotificationTrigger` on task create/update when there's a future due date (gated by `taskRemindersEnabled`); cancel the request on complete/delete; schedule the due-today digest on launch. |
