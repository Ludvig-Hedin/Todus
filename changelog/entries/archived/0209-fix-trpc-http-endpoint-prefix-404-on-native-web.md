---
id: 0209
title: "Fix – tRPC HTTP endpoint prefix (404 on native + web)"
status: archived
category: Fixed
release_date: 2026-04-24
source: CHANGELOG.md
---

## [2026-04-24] Fix – tRPC HTTP endpoint prefix (404 on native + web)

- [Fix] Set `@hono/trpc-server` `endpoint` to `/api/trpc` so `fetchRequestHandler` strips the full pathname correctly (`/api/trpc/meet.listMeetings` → `meet.listMeetings`). The previous `/trpc` value left a `trpc/...` remainder and all procedures returned **HTTP 404**.
- **File:** `apps/server/src/main.ts`
