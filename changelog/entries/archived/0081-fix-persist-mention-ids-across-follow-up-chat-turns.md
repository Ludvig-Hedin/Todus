---
id: 0081
title: "Fix — Persist Mention IDs Across Follow-up Chat Turns"
status: archived
category: Fixed
release_date: 2026-03-29
source: CHANGELOG.md
---

## [2026-03-29] Fix — Persist Mention IDs Across Follow-up Chat Turns

### Summary

Mentions (e.g. `@thread X`, `@task Y`) only resolved for the turn they were inserted in. The underlying entity IDs were stored in a transient `currentTurnMentions` array that was cleared after each stream, while prior messages were serialized as plain text. A multi-turn flow like "summarize @thread X" → "reply to it" would lose the resolved thread ID on the second turn.

**Fix:** Added a `mentions: [RichInputMentionRef]` property to `AIChatMessage` so each user message persists its mention refs. `buildPayload` now collects de-duplicated mentions from ALL user messages in the conversation history (not just the current turn), ensuring entity IDs remain resolvable across follow-up turns.

**Files changed:**

- `apps/ios/Todus/Todus/Features/AI/AIChatMessage.swift` — Added `mentions` property and init parameter
- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift` — Store mentions on user message at send time; `buildPayload` collects mentions from all user messages with de-duplication
