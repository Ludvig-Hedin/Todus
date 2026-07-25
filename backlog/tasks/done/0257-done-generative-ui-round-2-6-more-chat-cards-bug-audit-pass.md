---
id: 0257
title: "DONE Generative-UI round 2: 6 more chat cards + bug-audit pass (2026-04): Added AttachmentCard, Code"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Native Fix Batch

- `DONE` **Generative-UI round 2: 6 more chat cards + bug-audit pass (2026-04):** Added `AttachmentCard`, `CodeBlockCard`, `ChecklistCard`, `DocumentCard`, `WeeklyAgendaCard`, `MetricCard` across web / iOS / macOS, plus four new actions (`open_attachment`, `toggle_checklist_item`, `navigate_document`, `navigate_day`). Bug audit fixes: autosave/send race in `InlineComposeCard` (debounce now cancelled on Send), iOS+macOS recipient dedupe + email validation, `groupedThreshold` now clamped to ≥1 on iOS+macOS, macOS `retryMessage` clears `uiSpec`, macOS `InlineCompose` no longer hangs in "Sending…" on failure (typealias migrated to 3-arg with completion), `CopyableTextCard` capped at ~280px with internal scroll, web InlineCompose displays attachment chips, iOS opens `previewUrl` via `UIApplication.shared.open` and macOS via `NSWorkspace.shared.open`.
