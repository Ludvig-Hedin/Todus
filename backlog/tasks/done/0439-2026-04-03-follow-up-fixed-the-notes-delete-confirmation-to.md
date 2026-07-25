---
id: 0439
title: "2026-04-03 follow-up: fixed the notes delete confirmation to use the generated Paraglide key, remove"
status: done
tags: [task-md, sprint]
files: [apps/mail/components/mail/note-panel.tsx, apps/mail/app/(routes)/settings/meetings/page.tsx, apps/server/src/trpc/routes/meet.ts, apps/server/src/routes/recall-webhook.ts, apps/server/src/lib/meeting-retention.ts]
created: 2026-03-01
source: TASK.md
---

> Source context: TASK.md → Session Notes (2026-03-01)

- 2026-04-03 follow-up: fixed the notes delete confirmation to use the generated Paraglide key, removed the non-functional meeting notification toggles from the new meetings settings page, added automatic cleanup for expired meeting recordings, and expanded calendar sync so previously imported future meetings are also auto-scheduled for recording. User-facing and architectural change in `apps/mail/components/mail/note-panel.tsx`, `apps/mail/app/(routes)/settings/meetings/page.tsx`, `apps/server/src/trpc/routes/meet.ts`, `apps/server/src/routes/recall-webhook.ts`, and `apps/server/src/lib/meeting-retention.ts`.
