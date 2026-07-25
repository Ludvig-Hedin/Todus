---
id: 0126
title: "Feature — S1: Google Calendar integration (backend + web)"
status: archived
category: Added
release_date: 2026-03-31
source: CHANGELOG.md
---

## [2026-03-31] Feature — S1: Google Calendar integration (backend + web)

### Backend — `calendar.ts` + `trpc/index.ts` + `driver/google.ts`

- New `calendarRouter` with `events` and `calendars` queries — calls Google Calendar API v3 using `OAuth2Client` (auto-refresh via stored `refreshToken`)
- `calendar.readonly` scope added to Google driver's `getScope()` — included in all new auth flows
- 403 "scope missing" handled gracefully: returns `{ events: [], scopeMissing: true }` so the frontend can prompt a re-auth rather than surfacing an error

### Web — `calendar/page.tsx`

- Calendar page now fetches real Google Calendar events for the displayed month
- Right panel shows events (colored left border, time, location) above tasks; unified empty state
- Week overview shows blue dots on days with events
- `scopeMissing = true` → "Connect Google Calendar" banner with `authClient.linkSocial` re-auth
- Page title reverted to "Calendar" now that real events are shown

**Files:** `apps/server/src/trpc/routes/calendar.ts` (new), `apps/server/src/trpc/index.ts`, `apps/server/src/lib/driver/google.ts`, `apps/web/app/(routes)/mail/calendar/page.tsx`
