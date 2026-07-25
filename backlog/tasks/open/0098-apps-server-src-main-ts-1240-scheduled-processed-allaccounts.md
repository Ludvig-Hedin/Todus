---
id: 0098
title: "apps/server/src/main.ts:1240 — \\[SCHEDULED] Processed ${allAccounts.keys.length} accounts\\ — allAccounts.keys"
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
| `apps/server/src/main.ts:1240` | 🟡 medium | `\`[SCHEDULED] Processed ${allAccounts.keys.length} accounts\`` — `allAccounts.keys` resolves to `Array.prototype.keys` (a function with `.length === 0`), so the log always reports 0 accounts. | `allAccounts.length`. |
