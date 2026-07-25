---
id: 0051
title: "iOS Splash screen redesign + brand icon fixes"
status: archived
category: Fixed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS Splash screen redesign + brand icon fixes

### Splash Screen

- **Before**: Plain "Todus" text + spinner — no visual identity.
- **After**: Branded rounded-square app icon mark (checklist SF Symbol, 96pt) + "Todus" title (rounded bold) + spinner below. (`TodosApp.swift`)

### Brand Icon Fixes

- **AppleRemindersLogo clipping**: Previous `rowSpacing = h * 0.27` caused total content (1.14h) to overflow the frame, clipping the orange 3rd row. Reduced to `h * 0.11`; all 3 rows now fit at every size. (`BrandIcons.swift`)
- **AppleRemindersIconView**: Refactored to use `AppIconContainer` (same pattern as GmailIconView) — white rounded-rect background with proper breathing room. No more stretching to fill the frame.
- **AppIconContainer padding**: Inner icon frame reduced from `size * 0.72` to `size * 0.62` — ~19% padding on each side so icons feel airy.

### Files

- `apps/ios/Todus/Todus/App/TodosApp.swift` — branded splash
- `apps/ios/Todus/Todus/DesignSystem/BrandIcons.swift` — spacing fix, padding fix, AppleRemindersIconView refactor
