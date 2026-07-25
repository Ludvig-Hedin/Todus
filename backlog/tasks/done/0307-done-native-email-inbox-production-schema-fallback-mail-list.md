---
id: 0307
title: "DONE Native Email Inbox production schema fallback: mail.listThreads / active connection resolution"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Web/Server Fix Batch

- `DONE` Native Email Inbox production schema fallback: `mail.listThreads` / active connection resolution no longer fail when `mail0_connection.color` is missing, multi-connection mail reads use the same legacy query, `assistant.listOpenLoops` returns no nudges when second-brain tables are not migrated, and bearer-token requests keep the real backend error instead of masking it with a failed sign-out/get-session path.
