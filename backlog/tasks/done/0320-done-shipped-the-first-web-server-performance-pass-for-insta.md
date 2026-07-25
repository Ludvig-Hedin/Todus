---
id: 0320
title: "DONE Shipped the first web/server performance pass for instant-feeling mail and tasks: inbox rows no"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Web/Server Fix Batch

- `DONE` Shipped the first web/server performance pass for instant-feeling mail and tasks: inbox rows now render from thread summaries instead of per-row `mail.get` calls, thread detail is predictively prefetched, startup warmup preloads inbox/tasks/calendar/settings data, task mutations now patch cached task lists directly, and cached-first surfaces now show a subtle background-refresh indicator while data revalidates.
