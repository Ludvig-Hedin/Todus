---
id: 0295
title: "iOS — drop stale v1 inbox cache so new mail isn't pinned below stuck rows"
status: archived
category: Added
release_date: 2026-05-21
source: CHANGELOG.md
---

## [2026-05-21] iOS — drop stale v1 inbox cache so new mail isn't pinned below stuck rows

After the sync recovery landed, returning iOS users saw fresh mail load correctly but ~30 legacy threads stayed pinned at the top of the inbox. Root cause: the v1 cache file (`email_inbox_threads_v1` in UserDefaults) was written while the backend's Gmail continuous sync was disabled, so some rows had a `latestReceivedOn` that had fallen back to `Date()` (now) inside `syncThread`'s date-normalization catch. Those rows now have a permanent future-ish date, which kept anchoring `currentNewest` ahead of every real incoming row and tripping the `isStaleRefresh` guard that keeps the cache when it looks newer than the network response.

- **Cache version bump v1 → v2** (`apps/ios/Todus/Todus/Services/Email/EmailService.swift`) — New `cacheDataKey` / `cacheTimestampKey` so the next launch starts from a clean cache built from the fresh backend response. Legacy v1 keys are explicitly removed on `init` and on `resetForSignOut` to avoid leaking orphaned bytes.
- **Sanity filter on cache load** (`apps/ios/Todus/Todus/Services/Email/EmailService.swift`) — `loadCachedThreads` now drops any thread with a date more than a day in the future or earlier than 2000-01-01. Belt-and-suspenders for future regressions that would otherwise re-stamp `Date()` into the cache and re-create the same symptom.
