---
id: 0180
title: "Deferred items — 2026-06-15 second-wave resolution"
status: done
tags: [ios, ux, code-review-backlog]
files: []
created: 2026-06-15
source: CODE_REVIEW_BACKLOG.md
---

> Source context: iOS UX hardening pass — 2026-06-15 (whole-app, main user-flow surfaces)

## Deferred items — 2026-06-15 second-wave resolution

Second wave (6 implementer agents) cleared most of the deferred set. Whole-app `xcodebuild` re-verified after these + the file deletion below.

### ✅ Resolved in the second wave

| ID | Where | Resolution |
|----|-------|-----------|
| ~~UX-D1~~ | Board view | **Already existed** — `BoardColumnView` has an inline quick-add row calling `TaskCaptureService.captureInStatus(title:status:in:)`. Original deferral was wrong. |
| ~~UX-D2~~ | `FolderDetailView` / `fetchFolderContents` | `fetchFolderContents` now returns `FolderContentsResult { items, remoteFetchFailed }`; the view shows a distinct "Couldn't load — pull to refresh" state vs. genuine empty. |
| ~~UX-D4 (subset)~~ | AI chat edit-undo | Edit now captures the truncated tail + index (`lastTruncatedHistory` was previously dead — set to `[]` immediately); `restoreTruncatedHistory` + a 30s "Undo edit" chip wired via the existing `cancelStream()`. Branching / per-tool-retry / streaming-lag / per-source open remain deferred (see below). |
| ~~UX-D6~~ | AI delete confirmation | `PendingDeleteConfirmation` gained `subtitle`; the delete-task handler fetches due date + folder and the dialog shows "Due <date> · <folder>". |
| ~~UX-D7 (docs)~~ | `DocsService` / `DocsListView` | `lastSyncedAt` set on successful refresh; a "Last refreshed … ago" tap-to-sync footer mirrors MeetingsListView. |
| ~~UX-D9~~ | Cross-tab "See all N" | Added `tasksSearchSeed` (+ reused existing `pendingEmailSearchQuery`); GlobalSearchView seeds the query, Tasks & Email tabs consume it on appear. |
| ~~UX-D10~~ | Orphaned `EmailAIDraftSheet` | Confirmed zero external references; **deleted** the file and its 4 explicit `project.pbxproj` entries (legacy-style, not a synchronized group). Compose already uses AIChatView. |

### Still deferred — genuine risk / product decision (unchanged)

| ID | Where | Why still deferred |
|----|-------|--------------------|
| UX-D3 | `CalendarMonthView` row height | Size-class-adaptive height risks layout churn across the perf-tuned ±60-month buffer. |
| UX-D4 (rest) | AI chat — message branching, per-tool retry, streaming keystroke-lag, per-source "open in app" | Architectural / new UI + backend shape. |
| UX-D5 | `VoiceInputButton` transcribing-cancel | No cancel API; audio-path change, low value. |
| UX-D7 (Q&A) | Meeting Q&A timestamp sourcing | Needs backend response to carry transcript timestamps. |
| UX-D8 | Recipient display-name preservation in compose | Data-model change (`[String]` → `[Recipient]`) touching the send payload; needs integration testing before shipping. |

---
