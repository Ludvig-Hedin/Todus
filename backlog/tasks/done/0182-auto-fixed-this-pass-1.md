---
id: 0182
title: "Auto-fixed this pass (1)"
status: done
tags: [code-review, code-review-backlog]
files: []
created: 2026-06-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Pre-push full-repo review — 2026-06-20

## Auto-fixed this pass (1)

- `apps/server/src/routes/ai.ts:261` (`injectSearchContext`) — generic cast `{ role, content } as T` tripped TS2352 (the one diff-introduced type error; esbuild-harmless but flagged). Changed to the canonical `as unknown as T`; runtime identical, touched file now tsc-clean.
