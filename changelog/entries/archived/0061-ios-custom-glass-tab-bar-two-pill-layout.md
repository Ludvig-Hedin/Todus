---
id: 0061
title: "iOS — Custom glass tab bar (two-pill layout)"
status: archived
category: Changed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS — Custom glass tab bar (two-pill layout)

### Changed

- **Replaced system TabView** with a fully custom tab bar using `safeAreaInset(edge: .bottom)` — eliminates `tabViewBottomAccessory` full-width stretching issues entirely.
- **Two-pill layout**: left pill (4 nav tabs, fills width) + right pill (AI + Create, fixed size). Active tab shows filled icon + subtle blue rounded-rect indicator.
- **Glass material**: iOS 26 uses `.glassEffect(in: Capsule())` (Liquid Glass); iOS 17/18 uses `.ultraThinMaterial` capsule + drop shadow.
- **AI icon**: `lasso.badge.sparkles` with `.symbolRenderingMode(.multicolor)` for colorful rendering.
- **Create button**: "+" inside a small `Color.primary` filled circle (inverts in dark mode).
- **Content inset**: `safeAreaInset` pushes all content up automatically — no manual padding needed per-view.

### Files

- `apps/ios/Todus/Todus/Navigation/CustomTabBar.swift` ← new
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift` — stripped to content+safeAreaInset only
