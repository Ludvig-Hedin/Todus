---
id: 0065
title: "iOS Settings — Full overhaul with brand icons, better appearance, more options"
status: archived
category: Changed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS Settings — Full overhaul with brand icons, better appearance, more options

### Bug Fix

- **Settings buttons now work**: `hasSeenOnboarding` on `AuthService` changed from a computed UserDefaults property to a stored `@Observable` var. SwiftUI now detects the change and `RootView` correctly switches to `AuthView` when the user logs out or taps "Sign in". Previously, no observable change occurred when `authState` was already `.guest`. (`AuthService.swift`)
- **Cards visible in light mode**: `AppTheme.backgroundBottom/Top` changed from `0.99` to `0.94` in light mode, matching iOS `systemGroupedBackground`. List cells (white) now contrast clearly against the gray background. Dark mode surface raised slightly `0.09 → 0.11` to reduce harsh contrast. (`AppTheme.swift`)

### Feature: Brand Icons

- **`BrandIcons.swift`** (new): `GmailLogo` — pixel-accurate SVG-path recreation using `Canvas` + five filled paths (blue/green/yellow/red/dark-red). `AppleCalendarLogo` — red header + large day number. `AppleRemindersLogo` — three coloured dot rows. All wrapped in `AppIconContainer` with iOS-style rounded-rect background and shadow. (`BrandIcons.swift`)

### Feature: Improved Settings UI

- **Appearance selector**: Replaced `.segmented` picker with three visual preview cards (mini mock-UI swatch + icon + label). Selection shows blue border + checkmark. (`SettingsView.swift`)
- **Account section**: Avatar circle with email initial, green/orange status dot, cleaner layout.
- **Connected Services**: Proper brand icons with connection status. Apple Calendar shows "Connect" button when not authorized.
- **New sections**: Email (thread grouping, unsubscribe, signature, swipe actions), AI Assistant (task read/write toggles), Privacy (app permissions, data sync info).
- **AI model picker**: Developer section `Model` row is now a `Picker` showing all `preferredModels`, directly bound to `aiChatService.selectedModel` via `@Bindable`.
- **Log out button**: Always says "Log out" (was conditionally "Return to Login"). (`SettingsView.swift`)
