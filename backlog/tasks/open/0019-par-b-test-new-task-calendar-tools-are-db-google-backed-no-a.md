---
id: 0019
title: "PAR-B-TEST — New task/calendar tools are DB/Google-backed; no automated test (server suite has no DB harness)."
status: open
priority: P3
tags: [web, code-review-backlog]
files: [apps/server/src/routes/agent/tools.ts]
created: 2026-06-13
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Web → Native parity — deferred sub-items (2026-06-13)

| ID | Area | Where | Problem | Suggested fix |
|----|------|-------|---------|---------------|
| PAR-B-TEST | AI tools | `apps/server/src/routes/agent/tools.ts` | New task/calendar tools are DB/Google-backed; no automated test (server suite has no DB harness). Verified via tsc + server test suite (no import/compile breakage). | Add integration tests once a DB/Google harness exists; for now manual verify via chat. |
