---
id: 0130
title: "UX Polish — email folder parity on iOS and macOS"
status: archived
category: Changed
release_date: 2026-03-31
source: CHANGELOG.md
---

## [2026-03-31] UX Polish — email folder parity on iOS and macOS

### iOS — `EmailInboxView.swift`

- Added `EmailFolder` private enum covering all 7 backend folders: inbox, drafts, sent, archive, snoozed, spam, bin (trash)
- Header title is now tappable — opens a `Menu` folder picker with icons, divided into primary (Inbox/Drafts/Sent) and secondary (Archive/Snoozed/Spam/Trash) groups
- Folder changes clear the search field and reload threads via `loadThreads(folder:refresh:)`
- Loading skeleton, empty state icon, and empty state title all reflect the active folder

### macOS — `MacRootView.swift` + `MacSidebarView.swift`

- Extended `EmailSection` enum with four new cases: `.archive`, `.snoozed`, `.spam`, `.bin` — each with a `title`, `systemImage`, and `isPrimary` flag
- Sidebar email sub-items now show icons alongside text (updated `SidebarChildItemButton` to accept optional `systemImage`)
- Primary folders (Inbox, Drafts, Sent) appear above a subtle divider; secondary folders below
- `MacEmailInboxView(folder: section.rawValue)` already routes the raw value to the backend — no additional changes needed

**Files:** `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`, `apps/macos/TodusMac/App/MacRootView.swift`, `apps/macos/TodusMac/App/MacSidebarView.swift`, `apps/macos/TodusMac/Views/Email/MacEmailInboxView.swift`
