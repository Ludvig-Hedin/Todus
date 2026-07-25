---
id: 0012
title: "Server tsc --noEmit reports type errors in routes/agent/mcp.ts, thread-workflow-utils/workflow-funct"
status: open
priority: P3
tags: [code-review, code-review-backlog]
files: [routes/agent/mcp.ts, thread-workflow-utils/workflow-functions.ts, lib/driver/microsoft.ts, lib/bulk-delete.ts, lib/analyze/interests.ts, lib/server-utils.ts]
created: 2026-06-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Pre-push full-repo review — 2026-06-20 → Pre-existing (not introduced by these commits — out of scope, left as-is)

- Server `tsc --noEmit` reports type errors in `routes/agent/mcp.ts`, `thread-workflow-utils/workflow-functions.ts`, `lib/driver/microsoft.ts`, `lib/bulk-delete.ts`, `lib/analyze/interests.ts`, `lib/server-utils.ts` — all in files **not** touched by this diff, mostly stale wrangler-`Env` binding noise. Do not block `wrangler deploy` (CF bundles via esbuild, no tsc gate). Pre-existing on `origin/main`.
