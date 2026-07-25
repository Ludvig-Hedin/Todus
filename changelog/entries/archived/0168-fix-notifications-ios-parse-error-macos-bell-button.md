---
id: 0168
title: "Fix — Notifications: iOS parse error + macOS bell button"
status: archived
category: Fixed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] Fix — Notifications: iOS parse error + macOS bell button

- **Backend fix:** `/api/ai/chat` was hardcoding `stream: true`, ignoring the `stream: false` sent by `NotificationDigestService`. Added `shouldStream` flag that respects the request param. Non-streaming requests now return the raw OpenAI completion JSON directly — fixing the iOS "couldn't be read because it isn't in the correct format" error.
- **macOS notifications bell:** Re-added the notifications toolbar button (previously removed as placeholder). Added `MacNotificationCenterView` — a macOS-native AI-powered digest sheet with the same logic as the iOS counterpart but adapted for `MacAppServices`. Uses a popover off the bell button.
- **macOS `TodosAPIClient`:** Made `baseURL` internal (was `private`) so `MacNotificationCenterView` can build the request URL.

**Files:** `apps/server/src/routes/ai.ts`, `apps/macos/TodusMac/Views/Notifications/MacNotificationCenterView.swift`, `apps/macos/TodusMac/App/MacRootView.swift`, `apps/macos/TodusMac/Services/API/TodosAPIClient.swift`, `apps/macos/TodusMac.xcodeproj/project.pbxproj`
