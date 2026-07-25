---
id: 0018
title: "PAR-B3 — Audit flagged that @-mention context may not actually be injected into the agent system prompt (UI-on"
status: open
priority: P3
tags: [web, code-review-backlog]
files: [apps/server/src/lib/mentions.ts]
created: 2026-06-13
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Web → Native parity — deferred sub-items (2026-06-13)

| ID | Area | Where | Problem | Suggested fix |
|----|------|-------|---------|---------------|
| PAR-B3 | AI context | `apps/server/src/lib/mentions.ts`, `apps/web` chat | Audit flagged that `@`-mention context may not actually be injected into the agent system prompt (UI-only). | Trace `injectMentionContextIntoMessages` end-to-end; confirm or fix. |
