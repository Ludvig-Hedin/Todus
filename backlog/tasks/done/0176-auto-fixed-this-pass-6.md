---
id: 0176
title: "Auto-fixed this pass (6)"
status: done
tags: [ios, bug-hunt, code-review-backlog]
files: []
created: 2026-06-14
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Bug Hunt — 2026-06-14 (iOS main user-flow surfaces)

## Auto-fixed this pass (6)

- `Features/Tasks/TaskRowView.swift:390` (`setPriority`) — `try? modelContext.save()` swallowed save errors → silent priority-change loss. Replaced with `do/catch` + `AppLogger`, matching `TaskCaptureService.capture`.
- `Services/Tasks/TaskCaptureService.swift:286` (`delete`) — `try? context.save()` swallowed; remote delete was enqueued even when the local delete failed → local/server divergence. Now `do/catch` and `return` before enqueue if the save throws.
- `Features/Voice/VoiceChatViewModel.swift:243-257` (`handleEvent .transcriptUpdate`) — out-of-order provider events (a partial arriving after `isFinal`) appended onto finalized text and corrupted the transcript. Added per-role `userTranscriptFinalized`/`assistantTranscriptFinalized` guards; reset in `finalizeCurrentTurn()`.
- `Navigation/CreateSheet.swift:1010` (compound-intent loop) — when `createEvent` failed (permission/EventKit) it set `eventSaveFallbackPrompt` and returned, but the loop kept creating the remaining intents and then `close()`d the sheet out from under the alert. Added `if eventSaveFallbackPrompt != nil { return }` after `createEvent`, mirroring the existing single-intent guard at `:1049`.
- `Features/Meetings/MeetingDetailView.swift:506` (`generateSummary`) — a failed post-action `loadMeeting()` nils `meeting`, replacing the just-generated summary with "Meeting not found". Now snapshots `meeting` and restores it if the refresh returns nil.
- `Features/Meetings/MeetingDetailView.swift:515` (`scheduleBot`) — same failed-reload-blanks-the-view defect; same snapshot/restore fix.
