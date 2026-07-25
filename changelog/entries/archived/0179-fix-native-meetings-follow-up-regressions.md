---
id: 0179
title: "Fix — Native meetings follow-up regressions"
status: archived
category: Fixed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] Fix — Native meetings follow-up regressions

### Native meetings (`apps/ios`, `apps/macos`)

- **MeetingDetailView.swift / MacMeetingDetailView.swift**: Detail refreshes after `generateSummary` and `scheduleBot` now preserve the current content instead of blanking the whole screen behind a full-screen loading spinner.
- **iOS MeetingsService.swift**: Calendar sync and bot scheduling now reload meetings with the current search/status filters preserved, so the visible list stays consistent with the active search field.
- **MacMeetingsView.swift**: Reordered grouped meeting sections to `Today → This Week → Upcoming → Earlier`, matching iOS and prioritizing the most time-sensitive meetings first.
- **iOS MeetingsListView.swift**: Removed the stale top-level duplicate and kept the active `Meetings/MeetingsListView.swift` implementation, which uses the same `Starting` label as the detail view for `bot_joining`.
