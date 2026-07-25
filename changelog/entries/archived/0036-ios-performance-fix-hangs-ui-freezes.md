---
id: 0036
title: "iOS Performance — Fix Hangs & UI Freezes"
status: archived
category: Fixed
release_date: 2026-03-26
source: CHANGELOG.md
---

## [2026-03-26] iOS Performance — Fix Hangs & UI Freezes

### Computed Property Caching (HIGH impact)

- **CalendarTaskView**: `buckets` computed property now cached in `@State`, recomputed only on `allTasks`/`searchText`/`selectedFolderID` changes instead of every body evaluation.
- **HomeView**: `tasksDueToday` cached in `@State`, recomputed on `allTasks` change.
- **EmailInboxView**: `filteredThreads` cached in `@State`, recomputed on `searchText`/`threads` change.
- **TaskTableView**: `visibleTasks` cached in `@State`, recomputed on `allTasks`/`selectedFolderID` change.
- **BoardView**: `filteredTasks(for:)` (called 4x per render) replaced with pre-grouped `@State` dictionary computed once.

### Startup Parallelization

- **RootView**: Auth upgrade and reminders setup now run concurrently via separate `.task` modifiers instead of sequentially.

### Settings Sheet Binding

- **MainTabView**: Replaced inline `Binding(get:set:)` with proper `@Bindable` pattern for `showsSettings`.

### Email Service Optimization

- **EmailService**: Batched parallel thread fetches into groups of 8 (was 30 simultaneous requests).

### Bug Fixes

- **EmailModels**: Fixed `EmailMessage` and `EmailAttachment` `Codable` → `Decodable` (they're only decoded from API responses, custom `CodingKeys` prevented `Encodable` synthesis).
- **EmailThread**: Added `Equatable` conformance for `.onChange(of:)` support.
