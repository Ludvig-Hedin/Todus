---
id: 0110
title: "Fix — macOS AI chat 401 handling (silent refresh parity with iOS)"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — macOS AI chat 401 handling (silent refresh parity with iOS)

`MacAIChatService` now mirrors iOS: on HTTP 401 from `/api/ai/chat`, call `attemptSilentRefresh()` before treating the session as dead. Success → user message to retry; failure → `isSessionExpired = true` and re-auth prompt.

**Files:** `apps/macos/TodusMac/Services/AI/MacAIChatService.swift`
