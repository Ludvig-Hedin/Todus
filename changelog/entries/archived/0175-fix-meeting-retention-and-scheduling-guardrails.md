---
id: 0175
title: "Fix — meeting retention and scheduling guardrails"
status: archived
category: Fixed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] Fix — meeting retention and scheduling guardrails

### Server (`apps/server`)

- **Migration 0045** (`apps/server/src/db/migrations/0045_meeting_retention_guardrails.sql`): Adds `last_pruned_at`, enforces unique `recall_bot_id`, and includes the duplicate-check guard before the constraint lands.
- **meeting-retention.ts**: Added staleness-aware pruning that writes `last_pruned_at`, returns a uniform `{ deleted }` shape, and stops scanning on every read.
- **trpc/routes/meet.ts**: Hardened Recall bot scheduling with an atomic claim before the external API call so concurrent syncs do not double-schedule the same meeting.
- **routes/recall-webhook.ts**: Moved retention cleanup out of the summary error path and fixed the summary sentinel rollback to use the in-scope claim flag.
- **db/schema.ts**: Matches the migration by adding the `last_pruned_at` integration column and making `recall_bot_id` unique.

### iOS (`apps/ios/Todus`)

- **AppServices.swift**: Tab bar restore now falls back to the default 4-tab layout when decoded persisted tabs are invalid or insufficient.
- **EmailService.swift**: Cached inbox data now checks staleness and refreshes in the background instead of leaving the timestamp fields unused.
- **TabBarCustomizationView.swift**: Fixed the delete handler to pass an `IndexSet` to `remove(atOffsets:)`.
