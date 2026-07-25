---
id: 0171
title: "Fix — macOS email thread: scroll passthrough + smarter AI assistant card"
status: archived
category: Fixed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] Fix — macOS email thread: scroll passthrough + smarter AI assistant card

- **Scroll fix:** Subclassed WKWebView as `PassthroughWKWebView` — overrides `scrollWheel(with:)` to forward events to `nextResponder` instead of consuming them. The outer SwiftUI `ScrollView` now scrolls the full thread no matter where the cursor is.
- **Assistant card redesign:** Removed raw "20% confidence" and "High risk" pills (technical internals, confusing to users). Card leads with plain-language actionable suggestions derived from `replyNeeded`, `meetingRequested`, `followUpNeeded`, `suggestedTasks` flags. `actionItems: [String]` rendered as a bullet list. Uncertainty note only shown when confidence < 40%. Buttons have `.help()` tooltips explaining disabled states. Loading skeleton while data fetches.

**Files:** `apps/macos/TodusMac/Views/Email/MacEmailThreadView.swift`
