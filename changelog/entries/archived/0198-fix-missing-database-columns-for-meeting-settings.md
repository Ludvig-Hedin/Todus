---
id: 0198
title: "Fix — Missing Database Columns for meeting settings"
status: archived
category: Fixed
release_date: 2026-04-06
source: CHANGELOG.md
---

## [2026-04-06] Fix — Missing Database Columns for meeting settings

- [Fix] Fixed an issue where the `meetIntegration` table in `db/schema.ts` was missing several columns (such as `auto_delete_days`, `last_pruned_at`, `auto_generate_summary`, etc.) that were being queried by the backend meetings endpoints, which resulted in a crash under `meet.listMeetings`.
- [Build] Generated a new Drizzle migration (`0049_fixed_karma.sql`) and pushed to the local database to apply the missing columns.
- **Files:** `apps/server/src/db/schema.ts`
