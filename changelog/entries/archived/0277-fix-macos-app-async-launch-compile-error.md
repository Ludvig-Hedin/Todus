---
id: 0277
title: "Fix — macOS app async launch compile error"
status: archived
category: Fixed
release_date: 2026-04-26
source: CHANGELOG.md
---

## [2026-04-26] Fix — macOS app async launch compile error

- [Fix] **macOS:** `TodusMacApp.initializeApp()` now awaits `Task.yield()`, matching the current Swift concurrency requirement and fixing the Xcode build error `Expression is 'async' but is not marked with 'await'` at app launch initialization.
- [Architectural] This keeps the existing splash-screen-first startup flow intact while making the deferred `ModelContainer` initialization compile correctly on current toolchains.
- **Files:** `apps/macos/TodusMac/App/TodusMacApp.swift`, `TASK.md`
