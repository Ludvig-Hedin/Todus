---
id: 0135
title: "UX Polish — cross-platform UX fixes (iOS, macOS, Web)"
status: archived
category: Fixed
release_date: 2026-03-31
source: CHANGELOG.md
---

## [2026-03-31] UX Polish — cross-platform UX fixes (iOS, macOS, Web)

Comprehensive UX pass addressing discoverability, friction, and honesty gaps across all three live platforms.

### macOS

- **Removed non-functional Quick Filters** from tasks sidebar footer — buttons had nil closures and did nothing (`MacSidebarView.swift`)
- **Removed hardcoded email labels & calendar sources** from sidebar footer — "Important/Work/Personal" labels and calendar source pills were static UI not backed by real data (`MacSidebarView.swift`)
- **Removed non-functional toolbar filter menus** — email (All Mail/Unread/Flagged) and tasks (All/Today/Upcoming/Completed) filters had empty closures; "Mark All Read" is the only remaining email toolbar action (`MacRootView.swift`)
- **Removed dead notification bell** — popover showed hardcoded "No new notifications." placeholder (`MacRootView.swift`)
- **Confirmed Email and AI Assistant are already separate sections** in `MacSettingsView.swift` — no change needed

### iOS

- **Split Settings: "Email & AI" → separate "Email" + "AI Assistant" sections** — reduces cognitive load; unrelated settings no longer grouped (`SettingsView.swift`)
- **Replaced horizontal-scroll sessions table with vertical cards** — mobile-friendly layout with "This device" badge and per-session log out (`SettingsView.swift`)
- **Added skeleton loading state to email inbox** — differentiates loading vs empty vs error; `.redacted(reason: .placeholder)` blocks shown during initial fetch (`EmailInboxView.swift`)

### Web

- **Honest Calendar page labeling** — title changed from "Calendar" to "Tasks by Date" with "Calendar events coming soon" badge; misleading "Connect Google Calendar" link removed (`calendar/page.tsx`)
- **Quick Actions on Search page** — initial empty state now shows inline task-create field (type + Enter) and "Compose new email" button, matching macOS quick-action pattern (`search/page.tsx`)

**Files:** `apps/macos/TodusMac/App/MacSidebarView.swift`, `apps/macos/TodusMac/App/MacRootView.swift`, `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`, `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`, `apps/web/app/(routes)/mail/calendar/page.tsx`, `apps/web/app/(routes)/mail/search/page.tsx`
