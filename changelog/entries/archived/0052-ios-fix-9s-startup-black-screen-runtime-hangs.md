---
id: 0052
title: "iOS — Fix 9s Startup Black Screen & Runtime Hangs"
status: archived
category: Fixed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS — Fix 9s Startup Black Screen & Runtime Hangs

### Startup Black Screen Fix (CRITICAL)

- **TodosApp**: Deferred `AppServices` and `ModelContainer` initialization from synchronous `init()` to async `.task` context. Shows a branded splash screen immediately while services initialize in the background. Previously all 12+ services + SwiftData schema reconciliation ran synchronously before the first frame, causing a 9+ second black screen.
- **AIChatService**: Deferred `loadPersistedConversations()` (JSON deserialization from UserDefaults) to an async Task instead of running synchronously during init.

### Runtime Hang Fixes (from earlier session)

- Cached expensive computed properties (`buckets`, `tasksDueToday`, `filteredThreads`, `visibleTasks`, `tasksByStatus`) across 5 views to prevent recalculation on every body evaluation.
- Parallelized startup operations in RootView (auth upgrade + reminders setup).
- Fixed settings sheet binding with proper `@Bindable` pattern.
- Batched email thread fetches from 30 simultaneous to groups of 8.
- Fixed `EmailMessage`/`EmailAttachment` `Codable` → `Decodable`, added `Equatable` to `EmailThread`.
