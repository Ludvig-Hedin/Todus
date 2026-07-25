---
id: 0346
title: "DONE Fixed production native Gmail linking 401s by sending the app's stored refresh/session token to"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Web/Server Fix Batch

- `DONE` Fixed production native Gmail linking 401s by sending the app's stored refresh/session token to `/auth/native-link-social` and validating that exact Better Auth session before forwarding to `link-social`.
