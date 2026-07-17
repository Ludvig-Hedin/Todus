# iOS Tasks tab UX overhaul — design

Date: 2026-07-17. Approved by Ludvig (chat). Scope: iOS app only (list mode primarily); server gains one tRPC mutation.

## Problem

Tasks tab feels overwhelming, petite, noisy, cluttered. Hard to organize: moving a task to a folder takes swipe → sheet. Every row shows an identical "Todo" pill (no information). Rows are narrow tap targets.

## Design

### 1. Calmer rows, bigger targets (`TaskRowView`, `InboxView`)

- Row padding: vertical 9→13pt, horizontal 10→14pt; list row insets 4→6pt (smart buckets) / 2→5pt (flat). Rows remain variable height.
- Hide the status pill when `status == .todo` (the default). Status shows only for non-default states.
- Checkbox glyph 21→23pt inside the existing 40×40 target.

### 2. Auto-organize — hybrid rules + AI

- **Server**: `tasks.organize` tRPC mutation (privateProcedure). Input: unfiled tasks `{id,title,description}` + folders `{id,name}`. Uses `generateObject` with `resolveModelFromSettings` (same pattern as `ai/search.ts`). Output: `assignments: [{taskId, folderId|null, newFolderName|null}]`. Server sanitizes: unknown folderIds dropped, ≤2 distinct new folder names.
- **iOS**: organize logic lives in a `TaskCaptureService` extension (new file `TaskOrganizeService.swift`) since the service already owns `apiClient` + folder mutations.
  - Rules layer (instant, offline): folder-name token match against title/description assigns a proposal.
  - AI layer: remaining unfiled tasks sent to `tasks.organize`. Offline/unauth → rules-only.
- **UI**: sparkles "Organize" button in the search/sort bar → `OrganizeReviewSheet`: proposals grouped by destination folder, per-task toggle (default on), Apply moves everything accepted (creating proposed folders via `createFolderExclusive`). Nothing moves without Apply.
- **On create**: after remote enrichment, an unfiled task gets one folder suggestion (existing folders only) stored in new optional `TaskRecord.suggestedFolderID` (additive SwiftData field, not synced). Row shows a quiet chip "→ Folder ✓ ✕". Accept moves; dismiss clears. Never re-suggests.

### 3. Drag & drop

- Task rows `.draggable(task.id.uuidString)` (String payload, validated as UUID on drop).
- Folder cards in the Tasks-tab footer wrapped in a drop-target view: highlight on hover, drop → `captureService.move(task, to: folder)`.
- `FolderDetailView`: task rows draggable; dashed "Move back to Inbox" drop strip (visible when the folder contains tasks) → `move(task, nil)`.

## Out of scope

Board/table/calendar mode changes beyond shared row component; macOS/web parity; syncing `suggestedFolderID`.

## Error handling

- `tasks.organize` failure → proposals fall back to rules-only; sheet shows what it has (or "Nothing to organize").
- Apply uses existing offline-queued folder/move mutations; no new failure surface.

## Testing

- Build via xcodebuild (iPhone simulator), manual flow check in simulator.
- Server: typecheck; sanitation logic is pure and small.
