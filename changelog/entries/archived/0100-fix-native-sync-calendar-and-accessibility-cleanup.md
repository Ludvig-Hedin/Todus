---
id: 0100
title: "Fix — native sync, calendar, and accessibility cleanup"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — native sync, calendar, and accessibility cleanup

- Kept the marketing home avatar text consistent with the existing `adam.jpg` asset in both web shells.
- Restored a 44pt task-row checkbox hit area, removed the root macOS focus-ring suppression, and added a visible focus style to the Gmail connect button.
- Made macOS calendar month/all-day event pills tappable, tightened the time-grid math, and disabled the misleading empty delete actions.
- Added conversation-delete persistence so local removals survive sync, plus retry handling for pending backend deletes on iOS/macOS.
- Hardened the backend conversation upsert against cross-user overwrite, and aligned the latest migration with task checks, timestamp triggers, OAuth foreign keys, and the writing-style matrix column rename.

**Files:** `HomeContent.tsx` (web + mail), `TaskRowView.swift`, `CreateSheet.swift`, `TodosAPIClient.swift` (iOS + macOS), `MacRootView.swift`, `MacTheme.swift`, `MacEmailInboxView.swift`, `CalendarEventBlockView.swift`, `CalendarTimeGridView.swift`, `MacCalendarView.swift`, `AIChatService.swift` (iOS + macOS), `schema.ts`, `0039_brainy_junta.sql`, `0039_snapshot.json`, `conversations.ts`
