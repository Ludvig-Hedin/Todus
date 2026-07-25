---
id: 0099
title: "apps/server/src/main.ts:1295 — .post('/a8n/notify/:providerId') returns a response only when providerId === EP"
status: open
priority: P3
tags: [code-review, code-review-backlog]
files: []
created: 2026-05-27
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-27 — Multi-skill review of cross-platform local diff → Needs human review (5)

| File:line | Severity | Problem | Suggested fix |
|-----------|----------|---------|---------------|
| `apps/server/src/main.ts:1295` | 🟡 medium | `.post('/a8n/notify/:providerId')` returns a response only when `providerId === EProviders.google`. Other providers exit the try block, run `finally { span.end() }`, and the handler returns `undefined` → Hono surfaces a 500 / 404 instead of a meaningful status. | `return c.json({ message: 'ignored' }, 200)` as a fallback so callers don't retry forever. |
