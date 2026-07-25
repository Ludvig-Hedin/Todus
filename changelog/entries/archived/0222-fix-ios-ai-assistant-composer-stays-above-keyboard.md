---
id: 0222
title: "Fix — iOS AI assistant composer stays above keyboard"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — iOS AI assistant composer stays above keyboard

- [Fix] **iOS:** `MainTabView` no longer disables keyboard-safe-area handling for the entire shell. The floating custom tab bar still ignores keyboard movement, but sheets presented from the shell, including `AIChatView`, now keep their bottom insets attached to the keyboard correctly.
- [User-facing] In the AI assistant sheet, the multiline chat composer now grows upward only. The bottom controls stay above the keyboard instead of expanding underneath it.
- [Files] `apps/ios/Todus/Todus/Navigation/MainTabView.swift`, `CHANGELOG.md`
