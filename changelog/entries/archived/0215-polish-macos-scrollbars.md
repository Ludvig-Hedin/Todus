---
id: 0215
title: "Polish — macOS scrollbars"
status: archived
category: Changed
release_date: 2026-04-24
source: CHANGELOG.md
---

## [2026-04-24] Polish — macOS scrollbars

- [UI] macOS app now uses overlay scroll indicators: no track well, slim floating thumb that appears while scrolling and fades when idle; `NSScrollView` backgrounds are cleared so no strip shows behind the thumb.
- [UI] Follow-up: clear `NSClipView` backgrounds and re-apply chrome on layout for SwiftUI `ScrollView`s (AI assistant + group chat); in-scroll `MacScrollViewChromeAnchor` + `NSScroller` small control size; composer `NSTextView` scroll view uses shared `applyChrome`.
- **Files:** `apps/macos/TodusMac/DesignSystem/MacScrollStyle.swift`, `apps/macos/TodusMac/App/TodusMacApp.swift`, `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`, `apps/macos/TodusMac/Views/AI/MacGroupChatView.swift`
