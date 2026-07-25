---
id: 0459
title: "Investigated iOS cold-start logs and isolated the actionable failures to backend startup requests fo"
status: done
tags: [task-md, sprint]
files: []
created: 2026-04-26
source: TASK.md
---

> Source context: TASK.md → Startup Log Follow-up (2026-04-26)

- Investigated iOS cold-start logs and isolated the actionable failures to backend startup requests for `assistant.getBriefing` and `mail.listThreads`, both caused by an environment still missing the `mail0_connection.color` column.
