---
id: 0151
title: "iOS — Multi-account connections service and inbox filtering"
status: archived
category: Changed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] iOS — Multi-account connections service and inbox filtering

### iOS (`apps/ios/Todus`)

- **ConnectionsService:** New `@Observable` service (`Services/API/ConnectionsService.swift`) that fetches connected email accounts from the `connections.list` tRPC route, manages enabled/disabled filter state per account in UserDefaults, and exposes toggle/enableAll/setDefault/deleteConnection APIs.
- **AppServices:** Added `connectionsService` property so all views can access it via `@Environment(AppServices.self)`.
- **Settings — dynamic connections list:** The Connected Services section now shows a dynamic list of connected accounts from the backend (with colored circles, provider names, email addresses, and connection status) instead of the hardcoded Gmail row. Includes an "Add Account" button. Falls back to the legacy Gmail row when connections haven't loaded yet.
- **EmailInboxView — multi-account filter chips:** When 2+ accounts are connected, a horizontal chip bar appears below the folder quick-switch row. Each chip shows a colored dot and truncated email; tapping toggles that account's visibility. An "All" chip selects all accounts.
