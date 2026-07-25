---
id: 0017
title: "PAR-A2 — ✅ MOSTLY DONE — visibility toggles shipped via eventsMulti (no server change). REMAINING: (1) create"
status: open
priority: P3
tags: [web, code-review-backlog]
files: [apps/web/app/(routes)/mail/calendar/page.tsx, apps/server/src/trpc/routes/calendar.ts]
created: 2026-06-13
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Web → Native parity — deferred sub-items (2026-06-13)

| ID | Area | Where | Problem | Suggested fix |
|----|------|-------|---------|---------------|
| PAR-A2 | Calendar | `apps/web/app/(routes)/mail/calendar/page.tsx`, `apps/server/src/trpc/routes/calendar.ts` | ✅ MOSTLY DONE — visibility toggles shipped via `eventsMulti` (no server change). REMAINING: (1) create-on-specific-calendar picker in `EventEditDialog` (currently defaults to `primary`); (2) cross-connection editing — write mutations are `activeConnectionProcedure` so editing an event on a non-active connection's calendar fails; needs optional `connectionId` on `createEvent/updateEvent/deleteEvent`; (3) `calendar.calendars` is active-connection only, so the calendar list shows only the active connection's calendars. | Add `connectionId` to write mutations + a `calendarsMulti` query; add a calendar picker to the create dialog. |
