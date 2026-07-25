---
id: 0181
title: "Validation evidence"
status: done
tags: [code-review, code-review-backlog]
files: [package.json, pnpm-workspace.yaml, lib/schemas.ts, db/schema.ts]
created: 2026-06-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Pre-push full-repo review — 2026-06-20

## Validation evidence

- **Web** `react-router build` → exit 0, full prerender of all marketing routes.
- **Server** `wrangler deploy --env production --dry-run` → clean esbuild bundle, all production bindings resolved (VECTORIZE, HYPERDRIVE, AI, queues, KV, R2).
- **pnpm hygiene** — commit `f5e6f240` deleted `bun.lock` + bun-style `workspaces.catalog`/`patchedDependencies` from `package.json`. Verified safe: `pnpm-workspace.yaml` holds the identical `catalog:`, `patchedDependencies: novel`, and workspace globs (the source of truth). Not a breakage.
- **No DB schema changes** → no production migration required (only Zod `lib/schemas.ts` changed, not `db/schema.ts`).
