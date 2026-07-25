---
id: 0122
title: "Fix — Restore iOS AI chat endpoint and message actions"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — Restore iOS AI chat endpoint and message actions

Resolved the current native iOS AI chat regression where every prompt failed immediately with `⚠️ Server error (404).`

- updated the iOS AI chat and notification digest clients to call `/api/ai/chat`, matching the backend router mount
- added targeted assistant-message retry so retry replaces the tapped reply in place instead of appending a duplicate turn
- stabilized the assistant action row so the copy button always uses primary text color and keeps a fixed width while swapping between copy and checkmark states
- preserved existing streaming, search, reasoning, and tool-call handling in the AI chat service

**Files changed:**

- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`
- `apps/ios/Todus/Todus/Services/Notifications/NotificationDigestService.swift`
- `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`
- `apps/ios/Todus/TASK.md`
- `apps/ios/Todus/plan.md`
