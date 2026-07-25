---
id: 0125
title: "Fix — C2: Web home page — distinguish \"not connected\" from empty state"
status: archived
category: Fixed
release_date: 2026-03-31
source: CHANGELOG.md
---

## [2026-03-31] Fix — C2: Web home page — distinguish "not connected" from empty state

### Web — `home/page.tsx`

- **Calendar section**: Replaces static "Connect Google Calendar" CTA with real `trpc.calendar.events` query for today. Shows live events with colored left border, time, and optional location. `scopeMissing = true` → re-auth button. No events → "No events today".
- **Email section**: Checks `threadsQuery.isError` to surface "Connect Gmail" CTA (backend returns `NOT_FOUND` when no connection) vs "Your inbox is empty" when connected with no threads.
- Added `CalendarEventRow` component for compact event rendering (colored border, time label, location).

**Files:** `apps/web/app/(routes)/mail/home/page.tsx`
