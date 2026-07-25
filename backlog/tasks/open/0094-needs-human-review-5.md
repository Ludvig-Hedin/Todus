---
id: 0094
title: "Needs human review (5)"
status: open
priority: P3
tags: [code-review, code-review-backlog]
files: [apps/server/src/main.ts]
created: 2026-05-27
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-27 — Multi-skill review of cross-platform local diff

> Section overview — the individual findings from this section are separate items.

## Needs human review (5)

Pre-existing bugs in `apps/server/src/main.ts` that are adjacent to the diff but were **not introduced by this batch of changes**. Surface here because `claude-review` flagged them during a full-file pass; fix in a separate PR with proper queue-semantics testing.
