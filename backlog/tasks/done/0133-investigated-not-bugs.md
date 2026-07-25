---
id: 0133
title: "Investigated, not bugs"
status: done
tags: [macos, bug-hunt, code-review-backlog]
files: []
created: 2026-05-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-20 — Bug Hunt: macOS app main user flows

## Investigated, not bugs

- **`apps/macos/TodusMac/Services/Drafts/MacDraftService.swift:173`** — `draft.connectionId` is non-optional `String` per `DraftRecord`; `.trimmingCharacters` is safe.
- **`apps/macos/TodusMac/Services/Voice/VoiceSessionCoordinator.swift:454`** — `executeTool` IS awaited inside the Task closure; no missing await.
- **`apps/macos/TodusMac/Views/Calendar/MacCalendarView.swift:1290-1294`** — Hour overflow when minute rounding hits 60: Foundation `Calendar.date(from:)` normalizes out-of-range components (e.g. hour=24 → next day 00:00). Safe.
- **`apps/macos/TodusMac/Views/Notifications/MacNotificationCenterView.swift:516`** — Request-ID guard correctly captures ID before await and compares after; not a race.
- **`apps/macos/TodusMac/Domain/TaskSmartSort.swift:72`** — Today-bucket-before-overdue ordering is the documented intent (`.today: "Needs attention now"`).
- **`apps/macos/TodusMac/Views/Meetings/MacMeetingDetailView.swift:458`** — Calling `loadMeeting()` after `generateSummary` failure is intentional refresh; `actionError` is also set.
