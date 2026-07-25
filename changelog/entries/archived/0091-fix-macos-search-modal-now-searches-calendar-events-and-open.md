---
id: 0091
title: "Fix — macOS search modal now searches calendar events and opens real actions"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — macOS search modal now searches calendar events and opens real actions

- Wired the macOS search modal to actual app callbacks so quick actions now open task creation, email compose, and new event flows instead of rendering inert rows.
- Added calendar event loading and search indexing to the modal so event names from the home dashboard now appear in search results.
- Improved the empty state with actionable suggestions and tap targets for common follow-up actions.
- Added direct navigation for search results so task, email, and event rows move the user into the right surface instead of doing nothing.

**Files:** `apps/macos/TodusMac/Views/Search/MacSearchView.swift`, `apps/macos/TodusMac/App/MacRootView.swift`
