---
id: 0078
title: "BH-0601-1 — Before shipping any Slack feature: run pnpm --filter @zero/server db:generate (only schema drift s"
status: open
priority: P2
tags: [bug-hunt, code-review-backlog]
files: [apps/server/src/db/migrations/0056_slack_connection.sql, meta/_journal.json, _journal.json, 0056_snapshot.json]
created: 2026-06-01
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-01 — Bug hunt (uncommitted + last 3 commits) → Needs attention (not auto-fixed)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| BH-0601-1 | DB migration | `apps/server/src/db/migrations/0056_slack_connection.sql` + `meta/_journal.json` | ⚠️ high (future), 🔵 none today | Migration 0056 is **orphaned**: not registered in `_journal.json` (last idx = 55) and has no `0056_snapshot.json`. `drizzle-kit migrate` reads the journal, not the directory, so it silently **skips** 0056 — `mail0_slack_connection` is never created. The `slackConnection` schema is currently queried **nowhere** (dormant scaffold), so there is **no user impact today**. | Before shipping any Slack feature: run `pnpm --filter @zero/server db:generate` (only schema drift since 0055 is `slackConnection`, so it should regenerate cleanly) to produce the journal entry + snapshot, then `db:migrate`. Did NOT auto-run regen — mid-flight schema, risk of picking up unrelated drift; needs a human to eyeball the generated diff. |
