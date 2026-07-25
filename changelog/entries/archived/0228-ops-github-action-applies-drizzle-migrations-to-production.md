---
id: 0228
title: "Ops — GitHub Action applies Drizzle migrations to production"
status: archived
category: Changed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Ops — GitHub Action applies Drizzle migrations to production

- [Ops] **db-migrate-production** workflow (manual + on push to `main` when server migrations change) runs `pnpm run -C apps/server db:migrate` with the **`PRODUCTION_DATABASE_URL`** repository secret so `api.todus.app` stays aligned with the repo. Add the same **direct Postgres URL** as the Cloudflare Hyperdrive **origin** (see `docs/development/README.md`). Does not run from this repo alone until the secret is set and the workflow is triggered.
- **Files:** `.github/workflows/db-migrate-production.yml`, `docs/development/README.md`
