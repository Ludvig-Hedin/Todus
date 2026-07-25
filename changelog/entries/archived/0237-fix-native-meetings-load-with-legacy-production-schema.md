---
id: 0237
title: "Fix — Native meetings load with legacy production schema"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — Native meetings load with legacy production schema

- [Fix] **Backend:** `meet.listMeetings`, `meet.getMeeting`, `meet.getIntegration`, and calendar sync now tolerate production databases missing newer `mail0_meet_integration` settings/retention columns. The route falls back to the original integration columns with safe defaults and skips retention pruning when retention columns are absent, preventing HTTP 500s in iOS/macOS Meetings.
- [User-facing] Restores the native Meetings page instead of showing "Failed to load meetings. Server error (http 500)."
- **Files:** `apps/server/src/trpc/routes/meet.ts`
