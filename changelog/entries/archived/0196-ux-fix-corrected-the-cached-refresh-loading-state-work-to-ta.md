---
id: 0196
title: "UX Fix — Corrected the cached-refresh loading-state work to target the real web app in `apps/web`, added subtl"
status: archived
category: Fixed
release_date: 2026-04-04
source: CHANGELOG.md
---

[2026-04-04] [UX Fix] Corrected the cached-refresh loading-state work to target the real web app in `apps/web`, added subtle background update badges across inbox, home, tasks, and calendar, stopped invalidating restored inbox cache on startup, and switched the web home recent-mail panel to render from thread summaries instead of per-row thread fetches. User-facing and architectural change. (apps/web/components/ui/background-refresh-indicator.tsx, apps/web/components/mail/mail-list.tsx, apps/web/app/(routes)/mail/home/page.tsx, apps/web/app/(routes)/mail/tasks/page.tsx, apps/web/app/(routes)/mail/calendar/page.tsx, apps/web/providers/query-provider.tsx).
