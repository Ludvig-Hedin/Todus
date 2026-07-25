---
id: 0161
title: "UX — iOS email thread view polish pass"
status: archived
category: Changed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] UX — iOS email thread view polish pass

### iOS (`apps/ios/Todus`)

- **Tab bar hidden in thread view:** Added `hideTabBar` flag to AppServices so the custom floating tab bar hides when viewing an email thread. Reply buttons are now fully visible.
- **Header redesign:** Removed solid background, replaced with transparent-to-scrim gradient. Action icons (mark unread, archive, delete) grouped in a single glass capsule. Back button and Ask AI button are standalone circles.
- **Ask AI in header:** Added sparkles button with the same gradient as the tab bar AI icon. Opens the AI chat sheet with thread context attached.
- **Bottom reply bar:** Removed solid background/blur. Reply/Reply all/Forward buttons now float freely with a subtle scrim gradient that fades content out behind them.
- **Scroll-aware title:** Subject appears centered in the header at body text size (15pt medium) when scrolled past the subject row.
- **Summary card trimmed:** AI summary capped at 3 lines, action items at 3 bullets max. Keeps the card compact and scannable.
- **Contextual action buttons:** Buttons now only appear when relevant — Extract task (when AI found tasks), Draft reply (when reply needed), Book follow-up (when follow-up flagged), Create event (when meeting detected). No more irrelevant buttons.
- **Action buttons unclipped:** Moved padding inside the ScrollView HStack so right-side pills are no longer clipped by parent padding.

### Files changed

- `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift` — Full rewrite
- `apps/ios/Todus/Todus/App/AppServices.swift` — Added `hideTabBar` property
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift` — Conditionally hide custom tab bar
