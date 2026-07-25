---
id: 0317
title: "Added — iOS Tasks: auto-organize, drag & drop, calmer rows"
status: unreleased
category: Added
release_date: 2026-07-17
source: CHANGELOG.md
---

### Added — iOS Tasks: auto-organize, drag & drop, calmer rows, 2026-07-17

UX overhaul of the Tasks tab (spec: `docs/superpowers/specs/2026-07-17-ios-tasks-ux-overhaul-design.md`):

- **Auto-organize (hybrid rules + AI)** — new sparkles "Organize" button in the search bar opens a review sheet: instant rule layer (folder-name word match) plus a new `tasks.organize` tRPC mutation (`generateObject`, existing-folder assignment + ≤2 proposed new folders, server-sanitized). Proposals are grouped by destination with per-task toggles; nothing moves without Apply. Offline → rules-only. iOS logic in `TaskOrganizeService.swift` (a `TaskCaptureService` extension).
- **On-create folder suggestion** — after enrichment, an unfiled capture gets one quiet "Move to X? ✓ ✕" chip on its row (new local-only `TaskRecord.suggestedFolderID`; accept moves, dismiss never re-suggests). Suggestion runs before the sync enqueue so it never waits on the network.
- **Drag & drop** — task rows are draggable (UUID payload); folder cards on the Tasks tab are drop targets (accent highlight on hover), and `FolderDetailView` gained a dashed "drag here to move back to Inbox" strip for dragging tasks out.
- **Calmer rows** — the default "Todo" status pill is hidden (status shows only for non-default states), row padding 9/10→13/14, list row insets up, checkbox glyph 21→23 pt. Fixed a SwiftUI gotcha where the suggestion chip's async name fetch hung off an `EmptyView` and never fired — the name now resolves synchronously in the row.
