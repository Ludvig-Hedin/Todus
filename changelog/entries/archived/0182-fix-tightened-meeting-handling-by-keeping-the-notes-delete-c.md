---
id: 0182
title: "Fix — Tightened meeting handling by keeping the notes delete confirmation on a real Paraglide key, auto-schedu"
status: archived
category: Removed
release_date: 2026-04-03
source: CHANGELOG.md
---

[2026-04-03] [Fix] Tightened meeting handling by keeping the notes delete confirmation on a real Paraglide key, auto-scheduling future meetings that already exist in sync results, and pruning expired recording media based on the new retention setting. User-facing and architectural change. (apps/mail/components/mail/note-panel.tsx, apps/server/src/trpc/routes/meet.ts, apps/server/src/routes/recall-webhook.ts, apps/server/src/lib/meeting-retention.ts).
