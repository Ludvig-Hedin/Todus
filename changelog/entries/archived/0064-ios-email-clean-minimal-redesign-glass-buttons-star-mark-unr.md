---
id: 0064
title: "iOS Email — Clean minimal redesign, glass buttons, star + mark-unread"
status: archived
category: Changed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS Email — Clean minimal redesign, glass buttons, star + mark-unread

### Thread View

- **Header redesign**: Glass icon buttons (34×34) for back, star, mark-as-unread, archive, trash. Subject + sender name shown inline. Star derived from thread labels; toggles optimistically.
- **Mark as unread**: Taps `markAsUnread` + dismisses to inbox so the row shows unread immediately.
- **Cleaner message bubbles**: Sender row is a tap target for collapse; body has an inset section with hairline divider. Softer `rowStroke` border.
- **Header material**: `.ultraThinMaterial` with divider overlay.

### Inbox

- **Row separators**: `listRowSeparator(.visible)` with `AppTheme.divider` tint.
- **Loading indicator**: Inline spinner next to "Inbox" title during refresh.
- **Glass search bar**: `.glassEffect(in:)` on iOS 26; surface card fallback.
- **Unread accent bar**: 3pt vertical bar on left edge instead of floating dot.
- **Settings button**: Now uses `LiquidGlassButtonStyle`.

### Files

- `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailRowView.swift`
