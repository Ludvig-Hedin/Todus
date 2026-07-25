---
id: 0121
title: "Fix — Stabilize iOS AI chat history loading, duplication, and spec-only actions"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — Stabilize iOS AI chat history loading, duplication, and spec-only actions

Resolved a second set of AI chat state issues found during follow-up review.

- loading a saved chat now cancels any active AI stream first, so the newly loaded conversation does not inherit stale streaming/error state from the previous request
- duplicating a conversation now preserves the full in-memory message models, including mentions and assistant metadata, and leaves the duplicate marked unsaved so it can autosave normally
- assistant action rows now remain visible for spec-only replies that render native UI cards, while the copy action is disabled when there is no plain text payload to copy

**Files changed:**

- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`
- `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`
- `apps/ios/Todus/TASK.md`
- `apps/ios/Todus/plan.md`
