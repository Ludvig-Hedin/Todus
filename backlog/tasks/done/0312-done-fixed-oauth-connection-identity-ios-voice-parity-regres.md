---
id: 0312
title: "DONE Fixed OAuth connection identity + iOS voice parity regressions: server now resolves mailbox ide"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Web/Server Fix Batch

- `DONE` Fixed OAuth connection identity + iOS voice parity regressions: server now resolves mailbox identity from the provider account (not the app user), stores correct token expiry timestamps, and keeps provider fallback behavior safe for non-Google accounts; iOS voice tools now match supported task/calendar contracts and the stop-timeout path no longer drops the latest partial transcript.
