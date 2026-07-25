---
id: 0463
title: "mail.ts label modification has no batching"
status: open
priority: P3
tags: [server, todo-sweep, performance]
files: [apps/server/src/trpc/routes/mail.ts]
created: 2026-07-25
source: code TODO/FIXME sweep
---

`apps/server/src/trpc/routes/mail.ts:616` — `// TODO: Add batching`. Label mutations are issued one request at a time against the provider; a multi-thread action costs one round trip per thread.

## Fix shape

Use the provider's batch endpoint (Gmail `batchModify`) for the multi-id path and keep the single-id path as-is.
