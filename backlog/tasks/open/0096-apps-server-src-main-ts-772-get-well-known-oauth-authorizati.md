---
id: 0096
title: "apps/server/src/main.ts:772 — .get('.well-known/oauth-authorization-server', ...) is registered without a lead"
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
| `apps/server/src/main.ts:772` | ⚠️ high | `.get('.well-known/oauth-authorization-server', ...)` is registered without a leading slash. Hono pathnames always start with `/`, so the OAuth / MCP discovery endpoint 404s. | `.get('/.well-known/oauth-authorization-server', ...)`. |
