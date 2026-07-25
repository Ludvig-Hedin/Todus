---
id: 0107
title: "apps/ios/Todus/Todus/Services/AI/AIChatService.swift — claims of (a) partial JSON in tool arguments"
status: open
priority: P3
tags: [ios, bug-hunt, code-review-backlog]
files: [apps/ios/Todus/Todus/Services/AI/AIChatService.swift]
created: 2026-05-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-20 — iOS Mobile App Bug Hunt → Unverified leads (investigator candidates that need a closer look)

- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift` — claims of (a) partial JSON in tool arguments after `[DONE]` (line ~1115), (b) `executeToolCalls` not honouring cancellation between awaits (line ~1214), and (c) `syncLoadConversations` racing with local deletes (line ~2233). All plausible but require running the SSE parser and the delete handler concurrently to confirm.
