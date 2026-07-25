---
id: 0120
title: "Fix — Harden iOS AI chat history replay and UI-spec rendering"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — Harden iOS AI chat history replay and UI-spec rendering

Resolved three correctness issues in the native iOS AI chat flow that surfaced during code review.

- saved AI conversations now persist mention references alongside message text, so reopened chats keep task/thread/event IDs available for follow-up turns
- retrying an older assistant response now removes later dependent turns before replaying, preventing contradictory branched history from being sent back to the backend
- assistant replies that only contain a `ui-spec` block now clear the raw fenced JSON from the visible message body and render only the generated UI

**Files changed:**

- `apps/ios/Todus/Todus/Domain/AIChatConversation.swift`
- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`
- `apps/ios/Todus/Todus/Features/AI/AIChatMessage.swift`
- `apps/ios/Todus/TASK.md`
- `apps/ios/Todus/plan.md`
