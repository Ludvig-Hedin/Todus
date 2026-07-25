---
id: 0311
title: "DONE Native auth refresh compatibility: /api/auth/refresh-native-token now accepts both Better Auth"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Web/Server Fix Batch

- `DONE` Native auth refresh compatibility: `/api/auth/refresh-native-token` now accepts both Better Auth bearer tokens and the raw session token returned by `/auth/mobile-token`, rehydrating the latter through the signed cookie path before minting a fresh JWT so existing iOS/macOS sessions do not expire after 15 minutes; `NoRedirectDelegate` now stops at the first redirect so native auth bridge calls can inspect the original 3xx response instead of silently following it.
