---
id: 0203
title: "Fix — Frontend Vite tsconfig path resolution"
status: archived
category: Fixed
release_date: 2026-04-13
source: CHANGELOG.md
---

## [2026-04-13] Fix — Frontend Vite tsconfig path resolution

- [Fix] Scoped `vite-tsconfig-paths` in the frontend Vite configs to each app's local `tsconfig.json` so builds no longer crawl `apps/archived` and `reference/` configs that are outside the active app.
- [Build] Removed the noisy `TSConfckParseError` warnings caused by missing legacy/reference tsconfig dependencies during `pnpm --filter=@zero/mail build`.
- [Architectural] Kept the change surgical by fixing only Vite path-resolution scope; no route, runtime, or UI behavior changed.
- **Files:** `apps/mail/vite.config.ts`, `apps/web/vite.config.ts`
