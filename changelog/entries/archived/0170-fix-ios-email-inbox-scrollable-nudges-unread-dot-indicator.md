---
id: 0170
title: "Fix — iOS email inbox: scrollable nudges + unread dot indicator"
status: archived
category: Fixed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] Fix — iOS email inbox: scrollable nudges + unread dot indicator

- **Assistant nudges moved inside the List:** No longer a fixed header blocking ~40% of the screen. Now scrollable List rows at the top of the thread list — users see emails immediately and scroll nudges away naturally.
- **Unread indicator:** 3×40pt accent bar → 7pt circle dot with 18pt fixed-width cell for column alignment. Matches macOS app pattern.
- **Row padding:** `EmailRowView` uses symmetric `padding(.horizontal, 16)` now that it owns its own insets.

**Files:** `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`, `apps/ios/Todus/Todus/Features/Email/EmailRowView.swift`
