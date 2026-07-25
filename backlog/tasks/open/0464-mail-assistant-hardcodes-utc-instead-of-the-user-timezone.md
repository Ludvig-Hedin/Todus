---
id: 0464
title: "Mail assistant hardcodes UTC instead of the user timezone"
status: open
priority: P2
tags: [server, todo-sweep, ai]
files: [apps/server/src/trpc/routes/mail-assistant.ts]
created: 2026-07-25
source: code TODO/FIXME sweep
---

`apps/server/src/trpc/routes/mail-assistant.ts:368` — `// TODO: replace 'UTC' with the user's actual timezone once it's stored per user`. Assistant-derived dates ("tomorrow 9am") are computed in UTC, so users outside UTC get shifted times.

## Fix shape

Persist a timezone on the user settings record (the settings schema already syncs cross-platform) and thread it into the assistant date resolution. Falls back to UTC when unset.
