---
id: 0154
title: "Infra — Drizzle migration journal"
status: archived
category: Changed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] Infra — Drizzle migration journal

- **`apps/server/src/db/migrations/meta/_journal.json`:** Added missing entries for `0044_pale_luminals` and `0045_meeting_retention_guardrails` so `drizzle-kit migrate` runs them before `0046_assistant_second_brain`.
- **Note:** If the database was updated with `db:push` (or similar) while `__drizzle_migrations` only tracked through `0040`, `pnpm db:migrate` can fail with `relation "mail0_group" already exists`. Fix by inserting the SHA-256 hashes for already-applied migration SQL files into `drizzle.__drizzle_migrations` (matching `created_at` from the journal), or by resetting the local Docker Postgres volume when data loss is acceptable.
