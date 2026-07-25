---
id: 0129
title: "Fix — iOS: email inbox 4-state branching (loading / error / empty / results)"
status: archived
category: Fixed
release_date: 2026-03-31
source: CHANGELOG.md
---

## [2026-03-31] Fix — iOS: email inbox 4-state branching (loading / error / empty / results)

### iOS — `EmailInboxView.swift`

- Added `errorState` view: `exclamationmark.triangle` icon, "Couldn't load \(folder)" title, backend error message as subtitle, "Try Again" button
- Body condition now has 5 branches: no-connection → skeleton (isLoading && empty) → **error** (errorMessage != nil && empty && !loading) → empty → thread list
- `emptyState` now branches: search-empty ("No results for X", Clear Search button) vs folder-empty (folder icon, Refresh button)
- Fixed bug: `searchBar.onSubmit` was calling `loadThreads(query:refresh:)` without `folder:` — now passes `selectedFolder.rawValue`

**Files:** `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`
