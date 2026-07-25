---
id: 0256
title: "DONE Shared native auth session-restore hardening (2026-04): packages/swift-auth/AuthService now dis"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Native Fix Batch

- `DONE` **Shared native auth session-restore hardening (2026-04):** `packages/swift-auth/AuthService` now distinguishes refresh outcomes (`refreshed` vs revoked session vs transient failure), so offline launches with an expired JWT no longer raise a false session-expired banner. Confirmed-invalid sessions now sign out instead of leaving the app shell authenticated, and the debug token preview is fully redacted to length-only text.
