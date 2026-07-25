---
id: 0090
title: "Fix — Cloudflare install now respects the web workspace lockfile"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — Cloudflare install now respects the web workspace lockfile

- Regenerated `pnpm-lock.yaml` so the `apps/web` `uuid` / `@types/uuid` dependency entries match `apps/web/package.json` again.
- Kept the dependency update scoped to the lockfile only; no app source changes were required for this deploy fix.

**Files:** `pnpm-lock.yaml`
