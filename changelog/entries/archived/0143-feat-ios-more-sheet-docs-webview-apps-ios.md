---
id: 0143
title: "Feat — iOS More sheet + Docs WebView (apps/ios)"
status: archived
category: Docs
release_date: 2026-04-01
source: CHANGELOG.md
---

## [2026-04-01] Feat — iOS More sheet + Docs WebView (apps/ios)

Added "More" overflow button (ellipsis) to the custom tab bar that opens a sheet containing a Docs WebView:

- `Features/Docs/DocsWebView.swift` — WKWebView wrapper loading `https://app.todus.app/mail/docs`; injects Bearer token on initial load; mirrors device colour scheme via JS at document start.
- `Features/Docs/MoreSheetView.swift` — sheet with NavigationStack + List; single "Docs" row with `NavigationLink` to `DocsWebView`; Done button in toolbar.
- `Features/Tasks/CustomTabBar.swift` — added optional `onMore: (() -> Void)?` property; added ellipsis button (44×46pt, `secondaryLabel` colour) after the + button in the action pill.
- `Navigation/MainTabView.swift` — added `@State private var showMoreSheet`, passes `onMore: { showMoreSheet = true }` to `CustomTabBar`, presents `MoreSheetView` as a `.sheet`.
