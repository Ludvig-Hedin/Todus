---
id: 0152
title: "macOS — Multi-account connections service and sidebar integration"
status: archived
category: Changed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] macOS — Multi-account connections service and sidebar integration

### macOS (`apps/macos`)

- **ConnectionsService:** New `@Observable` service that fetches connected email accounts from the `connections.list` tRPC route, tracks enabled/disabled state per account in UserDefaults, and exposes toggle/enableAll/setDefault APIs.
- **MacAppServices:** Added `connectionsService` property so all views can access it via `@Environment`.
- **Sidebar accounts:** When multiple accounts are connected, the Email section shows per-account rows with colored dots and toggleable checkmarks. The sidebar footer shows a row of small colored avatar circles for quick multi-account switching.
