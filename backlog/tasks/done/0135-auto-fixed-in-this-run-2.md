---
id: 0135
title: "Auto-fixed in this run"
status: done
tags: [ios, bug-hunt, code-review-backlog]
files: []
created: 2026-05-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-20 — iOS Mobile App Bug Hunt

## Auto-fixed in this run

| ID | File:line | Status | What changed |
|----|-----------|--------|--------------|
| BH-2026-05-20-01 | `apps/ios/Todus/Todus/Services/AI/AIChatService.swift:2066` | fixed | `finaliseStream` set `isStreaming = false` *before* flushing `tokenBuffer` into the message. SwiftUI subscribers that read both flags could see the typing indicator disappear while the last tokens were still being appended. Moved the flag reset after the flush + `parseUISpec()`. |
| BH-2026-05-20-02 | `apps/ios/Todus/Todus/Services/Tasks/SupabaseSyncService.swift:42` | fixed | `enqueue()` on the `client == nil` path called `queue.popLast()?.continuation.resume()` *and then* `continuation.resume()`. The popped batch's continuation **is** the outer `continuation` (just appended one line above), so this double-resumed a `CheckedContinuation`, which traps with a fatal error. Replaced pop-then-resume with `queue.removeLast(); continuation.resume()`. |
