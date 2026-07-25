---
id: 0247
title: "Fix — macOS: Settings window no longer appears when logged out"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — macOS: Settings window no longer appears when logged out

- [Fix] **macOS:** The dedicated Settings `Window` used to be **restored at launch** if it had been open when the app quit, so it could reappear next to the sign-in UI. Settings now uses `defaultLaunchBehavior(.suppressed)` (only opens via ⌘, / menu / sidebar). When the login screen is shown or the user signs out, any open Settings window is closed programmatically.
