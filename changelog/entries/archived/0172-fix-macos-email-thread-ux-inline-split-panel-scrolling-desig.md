---
id: 0172
title: "Fix — macOS email thread UX: inline split panel, scrolling, design cleanup"
status: archived
category: Fixed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] Fix — macOS email thread UX: inline split panel, scrolling, design cleanup

- **Split-panel layout (macOS):** Email threads now open inline in a right-side detail pane instead of a modal sheet. Thread list (300px fixed) sits left, selected thread fills the right. Matches web app behavior.
- **Scrolling fixed:** `EmailHTMLView` (WKWebView) now measures its full content height via JS `scrollHeight` after page load and reports it via a `@Binding<CGFloat>`. The outer SwiftUI `ScrollView` handles all scrolling — no more tiny inner-scroll window.
- **Design cleanup:** Removed card background/border boxing from individual messages; messages flow with thin dividers. Removed per-message action buttons (redundant with assistant card). Simplified assistant card — removed nested inner summary card, flatter layout.
- **`onClose` param on `MacEmailThreadView`:** Inline mode calls `onClose()` to deselect; sheet mode (from search) continues to use `dismiss()`.

**Files:** `apps/macos/TodusMac/Views/Email/MacEmailInboxView.swift`, `apps/macos/TodusMac/Views/Email/MacEmailThreadView.swift`, `apps/macos/TodusMac/App/MacRootView.swift`
