---
id: 0278
title: "Fix — Hardened legacy mail connection fallback detection so wrapped shard/bootstrap errors that still originat"
status: archived
category: Removed
release_date: 2026-04-26
source: CHANGELOG.md
---

[2026-04-26] [Fix] Hardened legacy mail connection fallback detection so wrapped shard/bootstrap errors that still originate from a missing `mail0_connection.color` column no longer bypass the degraded-schema path during startup mail loads and assistant briefing fetches. Architectural safety fix. Manual follow-up: apply the existing backend migration `0047_connection_color.sql` in the environment serving `api.todus.app` to remove the fallback path entirely. (`apps/server/src/lib/server-utils.ts`).
