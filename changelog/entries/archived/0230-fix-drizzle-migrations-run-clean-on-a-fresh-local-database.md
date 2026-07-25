---
id: 0230
title: "Fix — Drizzle migrations run clean on a fresh local database"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — Drizzle migrations run clean on a fresh local database

- [Ops] **Backend:** `0044_pale_luminals.sql` no longer fails on `DROP INDEX "meet_integration_user_id_idx"` or duplicate recall unique blocks from `0043`. `0049_fixed_karma.sql` no longer re-creates assistant/marketing DDL already applied in `0046`–`0048`, so `pnpm db:migrate` completes on an empty DB. Local dev: `createdb todus` (or `psql -c 'CREATE DATABASE todus'`) before migrate; SQL like `CREATE ROLE` must run **inside** `psql`, not the shell.
- **Files:** `apps/server/src/db/migrations/0044_pale_luminals.sql`, `apps/server/src/db/migrations/0049_fixed_karma.sql`
