---
id: 0251
title: "DONE Assistant briefing fallback for shard-pool exhaustion (2026-04): assistant.getBriefing now trea"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Native Fix Batch

- `DONE` **Assistant briefing fallback for shard-pool exhaustion (2026-04):** `assistant.getBriefing` now treats `Timed out while waiting for an open slot in the pool` / shard-initialization fan-out failures as degraded-startup conditions and serves the lightweight fallback briefing instead of surfacing a 500 during Home startup.
