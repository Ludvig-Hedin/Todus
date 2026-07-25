---
id: 0026
title: "MAC-3 — A→B→A interleaved folder switches can let a slow superseded load commit to the cache (the live-threads"
status: open
priority: P3
tags: [macos, code-review, qa, code-review-backlog]
files: []
created: 2026-06-13
source: CODE_REVIEW_BACKLOG.md
---

> Source context: macOS QA pass — 2026-06-13 — email loading / thread-open / hangs → Needs human review (deferred)

| ID | Area | Where | Sev | Problem | Suggested fix |
|----|------|-------|-----|---------|---------------|
| MAC-3 | Email | `EmailService.loadThreads` folder-switch | 🟡 med | A→B→A interleaved folder switches can let a slow superseded load commit to the cache (the live-`threads` write is folder-guarded; the cache write is not). | Add a monotonic `loadGeneration` token; gate the cache write on it too. |
