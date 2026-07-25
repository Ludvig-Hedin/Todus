---
id: 0460
title: "Hardened server-side detection of the missing-column condition so wrapped durable-object / shard boo"
status: done
tags: [task-md, sprint]
files: []
created: 2026-04-26
source: TASK.md
---

> Source context: TASK.md → Startup Log Follow-up (2026-04-26)

- Hardened server-side detection of the missing-column condition so wrapped durable-object / shard bootstrap errors still trigger the legacy fallback path instead of returning a 500 during app startup.
