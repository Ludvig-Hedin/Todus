---
id: 0211
title: "Fix — Meetings API aligned with native apps"
status: archived
category: Fixed
release_date: 2026-04-24
source: CHANGELOG.md
---

## [2026-04-24] Fix — Meetings API aligned with native apps

- [Fix] `meet.listMeetings` now returns `total` (and normalizes `actionItems` to `{ task, owner, dueDate }` so AI `description` fields decode on iOS/macOS). Inputs accept JSON `null` for optional fields (Swift encoders send null; Zod previously rejected them).
- [Fix] `meet.getMeeting` returns a single flat payload with `transcript` and `media`, matching `MeetingDetailResponse` on native clients; web/mail meeting detail pages updated accordingly.
- [Fix] `meet.scheduleBot` includes `success: true` for the native `ScheduleBotResponse` type; `SyncResponse` on iOS/macOS now matches `syncFromCalendar` (`synced`, `total`, `autoRecorded`).
