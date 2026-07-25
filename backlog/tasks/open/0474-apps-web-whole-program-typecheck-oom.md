---
id: 0474
title: "apps/web cannot be typechecked whole-program — tsc OOMs at 11 GB heap"
status: open
priority: P2
tags: [web, tooling, dx]
files: [apps/web/tsconfig.json, apps/web/package.json]
created: 2026-07-25
---

`tsc --noEmit -p apps/web/tsconfig.json` never completes on a 24 GB machine. Observed
on 2026-07-25 across four runs:

- default heap → `FATAL ERROR: Ineffective mark-compacts near heap limit` at ~4.0 GB
- `--max-old-space-size=6144` → OOM at ~6.0 GB after ~5 min
- `--max-old-space-size=8192` → `Abort trap: 6`
- `--max-old-space-size=11264` → OOM at ~11.0 GB after ~20 min (GC pauses of 32 s)

Restricting `include` to ~10 entry files (`tsconfig.parity-check.json`, since deleted)
did **not** help — it still OOM'd at 6 GB, so the cost is in the transitive type graph,
not the file count. The prime suspect is the tRPC `AppRouter` / `Outputs` inference chain
pulled in from `@zero/server` via `@/providers/query-provider`: every page that calls
`useTRPC()` re-instantiates a very large conditional-type graph.

Consequence: there is currently **no whole-program type gate for `apps/web`**.
`bun run --filter=@zero/web build` (the documented gate in CLAUDE.md §7) passes, but Vite
transpiles without typechecking, so type regressions can land silently. `apps/web` has no
`typecheck` script for the same reason.

## Fix shape

Options, cheapest first:

1. Turn on `"incremental": true` + a committed `tsconfig.tsbuildinfo` path and see whether
   a warm run fits in memory.
2. Cut the inference cost at the boundary: export a pre-resolved `AppRouter` type from
   `@zero/server` (`.d.ts` emitted once) instead of re-inferring the router type in every
   web module.
3. Split the app into project references so pages typecheck in independent programs.
4. Failing all of the above, run the gate in CI on a larger runner and add a
   `typecheck` script that documents the required `--max-old-space-size`.

Until one of these lands, per-file `npx eslint <file>` plus the Vite build is the only
available verification for web changes, and that combination does not catch type errors.
