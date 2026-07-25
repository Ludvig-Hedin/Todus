---
id: 0042
title: "iOS — AI-powered Notification Center"
status: archived
category: Changed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS — AI-powered Notification Center

### New Feature

- **Notification Center sheet**: Tapping the bell icon in the app header now opens a notification center sheet (was: opened iOS system notification settings). The sheet shows an AI-generated digest of tasks due, upcoming calendar events, and important unread emails — grouped by type with priority indicators and tap-to-navigate actions.

### Architecture

- **NotificationDigestService** (`Services/Notifications/`): Sends local task/event/email data to `/ai/chat` with a specialized system prompt. Uses non-streaming mode for simpler JSON response parsing.
- **NotificationCenterView** (`Features/Notifications/`): SwiftUI sheet with loading skeleton, error/empty states, and grouped notification cards following existing HomeView design patterns.

### Files Changed

- `AppTheme.swift` — Bell button now opens NotificationCenterView sheet instead of system settings
- `NotificationDigestService.swift` — **NEW** — AI digest backend integration
- `NotificationCenterView.swift` — **NEW** — Notification center sheet UI
