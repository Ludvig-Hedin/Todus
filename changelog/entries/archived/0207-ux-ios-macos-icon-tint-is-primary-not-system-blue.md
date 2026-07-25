---
id: 0207
title: "UX — iOS & macOS: icon tint is primary, not system blue"
status: archived
category: Changed
release_date: 2026-04-24
source: CHANGELOG.md
---

## [2026-04-24] UX — iOS & macOS: icon tint is primary, not system blue

- [UX] Tab bar, toggles, lists, and AI chrome that used `Color.blue` or a blue accent now use `Color.primary` / primary text so SF Symbols and labels match the monochrome editorial look. macOS root `.tint` is `Color.primary` (the in-app accent picker no longer tints the whole shell).
- [UX] Group/shared chat and share CTAs that used “white on near-primary” were adjusted to primary-on-subtle fill so dark mode keeps readable contrast.
- **Files:** `AppTheme.swift` (`accentBlue`), `MainTabView.swift` (via token), `MacRootView.swift`, and affected feature views under `apps/ios/Todus` and `apps/macos/TodusMac`.
