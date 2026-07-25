---
id: 0066
title: "iOS Thread View — Auto-height body, swipe back, liquid glass, AI summary"
status: archived
category: Changed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS Thread View — Auto-height body, swipe back, liquid glass, AI summary

### Bug Fix

- **Email body no longer clipped**: Replaced fixed `maxHeight: 600` frame with dynamic WKWebView height measurement (`document.documentElement.scrollHeight` via `evaluateJavaScript`). Two-pass measurement (immediate + 700ms delay) handles late-loading images. Emails now expand to full content height.
- **`markAsRead` reliability**: Replaced `async let _ = markAsRead` with a named `async let` plus explicit `await` so the read request is not dropped (Swift structured-concurrency pitfall, see Swift #62027).
- **WKWebView flicker**: `EmailHTMLView.updateUIView` only calls `loadHTMLString` when raw `html` changes, not when height measurement updates state — avoids redundant reloads per message.

### Feature: Swipe-to-go-back

- **`SwipeBackEnabler`** (new in `AppTheme.swift`): `UIViewControllerRepresentable` that re-enables `interactivePopGestureRecognizer` after `.navigationBarBackButtonHidden(true)`. Applied to `EmailThreadView`.

### Feature: Liquid Glass Reply Button

- **`LiquidGlassButtonStyle`** (new in `AppTheme.swift`): Uses `.glassEffect(in:)` on iOS 26+, falls back to surface+border card on older iOS. Reply bar uses this style.

### Feature: AI Summary Card

- **`AISummaryCard`**: Collapsible summary at the top of the thread. Calls `brain.generateSummary` tRPC endpoint (uses `@cf/facebook/bart-large-cnn` — Cloudflare Workers AI, free tier). Only shown when the brain has vectorized the thread. Styled with a purple accent border matching the web app.

### Refactor

- `MessageBubble` now uses `SenderAvatarView` (size: 32) instead of its own initials/color logic.
- `EmailHTMLView` extracted into `ExpandingEmailHTMLView` wrapper — cleaner height state management.

### Files

- `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift`
- `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift`
- `apps/ios/Todus/Todus/Features/Email/SenderAvatarView.swift` (added `size` param)
