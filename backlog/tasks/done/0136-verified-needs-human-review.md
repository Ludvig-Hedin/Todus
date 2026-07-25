---
id: 0136
title: "Verified — needs human review"
status: done
tags: [ios, bug-hunt, code-review, code-review-backlog]
files: []
created: 2026-05-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-20 — iOS Mobile App Bug Hunt

## Verified — needs human review

| ID | File:line | Severity | Issue | Suggested fix |
|----|-----------|----------|-------|---------------|
| BH-2026-05-20-03 | `apps/ios/Todus/Todus/Features/Email/EmailAIDraftSheet.swift:257` | warning | `defer { Task { @MainActor in isStreaming = false } }` inside the outer `Task` schedules a *detached* hop to reset the flag. The outer `streamingTask` returns before the flag is reset, so a fast user can re-tap "Generate" while `isStreaming` is still true momentarily, or dismiss the sheet and have the detached Task mutate freed view state. | Replace the detached `Task` with an `await MainActor.run { isStreaming = false }` at the end of the outer Task body, or set the flag before the `defer` exits via direct assignment (the outer Task is already `@MainActor`-isolated via the enclosing view). |
| BH-2026-05-20-04 | `apps/ios/Todus/Todus/Services/Reminders/AppleRemindersSyncService.swift:286` | info | `completionDate = task.completed ? task.updatedAt : nil`. If a task was completed long after its last edit (e.g. updated at 9am, completed at 5pm), `completionDate` is set to the *edit* time, not the *completion* time. Surfaces in Reminders' "Completed" smart list with the wrong timestamp. | Track `completedAt` separately on `TaskRecord` and write that into Reminders, or write `.now` on the transition `false → true`. Skipped auto-fix because the model change is non-trivial. |
