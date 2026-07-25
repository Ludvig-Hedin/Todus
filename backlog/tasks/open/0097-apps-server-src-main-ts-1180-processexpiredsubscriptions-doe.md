---
id: 0097
title: "apps/server/src/main.ts:1180 — processExpiredSubscriptions does const { db, conn } = createDb(...), then await"
status: open
priority: P2
tags: [code-review, code-review-backlog]
files: []
created: 2026-05-27
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-27 — Multi-skill review of cross-platform local diff → Needs human review (5)

| File:line | Severity | Problem | Suggested fix |
|-----------|----------|---------|---------------|
| `apps/server/src/main.ts:1180` | ⚠️ high | `processExpiredSubscriptions` does `const { db, conn } = createDb(...)`, then `await db.query.connection.findMany(...)`, then `await conn.end()`. If `findMany` rejects, `conn.end()` never runs and the Hyperdrive / Postgres connection leaks. | Wrap the query in `try { … } finally { await conn.end() }`. |
